import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/automatic_sync.dart';
import 'package:waslapos_app/services/checkout_service.dart';
import 'package:waslapos_app/services/network_status.dart';
import 'package:waslapos_app/services/sync_service.dart';
import 'package:waslapos_app/services/wholesale_service.dart';

/// Sales invoices and receipts work online when the server answers and are
/// kept on the device and sent later when it does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
    await ApiClient.saveSession(
      token: 'token-1',
      session: {
        'user': {'id': 1, 'tenant_id': 1, 'branch_id': 3},
      },
    );
    ApiClient.offline.value = false;
  });
  tearDown(() {
    ApiClient.offline.value = false;
    ApiClient.client.close();
  });

  http.Response json(Object data, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  void noNetwork() => ApiClient.client = MockClient(
    (_) async =>
        throw http.ClientException("Failed host lookup: 'waslapos.app'"),
  );

  final invoice = <String, dynamic>{
    'branch_id': 3,
    'customer_id': 9,
    'items': [
      {'product_id': 2, 'quantity': 3, 'price': 10},
    ],
    'discount_amount': 5,
    'paid_amount': 10,
    'payment_method': 'cash',
  };
  final receipt = <String, dynamic>{
    'branch_id': 3,
    'customer_id': 9,
    'amount': 40,
    'payment_method': 'cash',
    'payment_date': '2026-11-22',
  };
  CheckoutService invoices() => CheckoutService(
    scope: 'sales-invoice-test',
    offlineEndpoint: 'pos/orders',
    requireOfflineShift: false,
    send: (payload) => ApiClient.post(
      Uri.parse('${ApiConfig.baseUrl}/pos/orders'),
      body: payload,
    ),
  );
  CheckoutService receipts() => CheckoutService(
    scope: 'receipt-test',
    resultKey: 'voucher',
    offlineEndpoint: 'wholesale/receipts',
    requireOfflineShift: false,
    send: (payload) => ApiClient.post(
      Uri.parse('${ApiConfig.baseUrl}/wholesale/receipts'),
      body: payload,
    ),
  );

  test(
    'the sales catalog loads from the device when the server cannot be reached',
    () async {
      ApiClient.client = MockClient(
        (_) async => json({
          'products': [
            {
              'id': 2,
              'name': 'قهوة',
              'price': 10,
              'stock_quantity': 4,
              'min_wholesale_quantity': 1,
            },
          ],
          'workspace_version': 1,
        }),
      );
      expect(await WholesaleService().fetchProducts(3), hasLength(1));

      // Opening the app again from scratch with no internet keeps the saved session and catalog.
      ApiClient.client.close();
      await ApiClient.initialize();
      expect(ApiClient.user?['id'], 1);
      noNetwork();
      final offline = await WholesaleService().fetchProducts(3);
      expect(offline.single['name'], 'قهوة');
      expect(ApiClient.offline.value, isTrue);
    },
  );

  test('without internet a sales invoice and a receipt are kept on the device, then sent once online', () async {
    noNetwork();
    final savedInvoice = await invoices().checkout(
      payload: invoice,
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    expect(savedInvoice['success'], isTrue);
    expect(savedInvoice['queued'], isTrue);
    expect(savedInvoice['order']['offline_pending'], isTrue);
    expect(savedInvoice['order']['total'], 25.0);
    expect(savedInvoice['order']['paid_amount'], 10);

    final savedReceipt = await receipts().checkout(
      payload: receipt,
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    expect(savedReceipt['queued'], isTrue);
    expect(savedReceipt['order']['amount'], 40);
    expect(savedReceipt['order']['voucher_number'], isNotEmpty);

    final pending = await ApiClient.offlineStore!.pendingOperations();
    expect(pending.map((row) => row['endpoint']), [
      'pos/orders',
      'wholesale/receipts',
    ]);
    expect(pending.every((row) => row['requires_shift'] == false), isTrue);
    expect(
      pending.every(
        (row) => !(row['payload'] as Map).containsKey('offline_shift_id'),
      ),
      isTrue,
    );

    final posted = <String>[];
    ApiClient.client = MockClient((request) async {
      if (request.method == 'POST') {
        posted.add(request.url.path);
        final body = jsonDecode(request.body) as Map;
        expect(body['operation_uuid'], isNotEmpty);
        return request.url.path.endsWith('/wholesale/receipts')
            ? json({
                'voucher': {'id': 71, 'voucher_number': 'RCV-71'},
              }, 201)
            : json({
                'order': {'id': 51, 'invoice_number': 'INV-51'},
              }, 201);
      }
      return json({'theme': 'blue'});
    });
    await SyncService.synchronize();

    expect(posted, ['/api/pos/orders', '/api/wholesale/receipts']);
    final records = await ApiClient.offlineStore!.operations();
    expect(records.map((row) => row['status']), everyElement('confirmed'));
    expect(records.map((row) => row['order']['id']), containsAll([51, 71]));
    expect(ApiClient.offline.value, isFalse);
  });

  test('with internet documents go straight to the server', () async {
    var posts = 0;
    ApiClient.client = MockClient((request) async {
      if (request.method == 'GET') return json({'active_shift': null});
      posts++;
      return json({
        'order': {'id': 8, 'invoice_number': 'INV-8'},
      }, 201);
    });
    final saved = await invoices().checkout(
      payload: invoice,
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    expect(saved['success'], isTrue);
    expect(saved['queued'], isNull);
    expect(posts, 1);
    expect(await ApiClient.offlineStore!.pendingOperations(), isEmpty);
  });

  test('editing a saved invoice or receipt still needs the server', () async {
    ApiClient.offline.value = true;
    noNetwork();
    final edit = await invoices().checkout(
      payload: {...invoice, 'invoice_id': 5},
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    expect(edit['success'], isFalse);
    expect(edit['message'], contains('يحتاج اتصالًا'));
    final receiptEdit = await receipts().checkout(
      payload: {...receipt, 'receipt_id': 6},
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    expect(receiptEdit['success'], isFalse);
    expect(await ApiClient.offlineStore!.pendingOperations(), isEmpty);
  });

  test('once offline, or when the network answers nothing, the saved copy opens without the long wait', () async {
    final catalog = {
      'products': [
        {'id': 2, 'name': 'قهوة', 'price': 10, 'stock_quantity': 4},
      ],
      'workspace_version': 1,
    };
    ApiClient.client = MockClient((_) async => json(catalog));
    await WholesaleService().fetchProducts(3);

    // Known offline: no request at all.
    var requests = 0;
    ApiClient.client = MockClient((_) async {
      requests++;
      return json(catalog);
    });
    ApiClient.offline.value = true;
    expect(await WholesaleService().fetchProducts(3), hasLength(1));
    expect(requests, 0);

    // Wi-Fi without internet: the request hangs, the saved copy is used after the short wait.
    ApiClient.offline.value = false;
    final previousWait = ApiClient.savedCopyWait;
    ApiClient.savedCopyWait = const Duration(milliseconds: 50);
    addTearDown(() => ApiClient.savedCopyWait = previousWait);
    ApiClient.client = MockClient((_) => Completer<http.Response>().future);
    final watch = Stopwatch()..start();
    expect(await WholesaleService().fetchProducts(3), hasLength(1));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(ApiClient.offline.value, isTrue);
  });

  test('the Android shell sends saved documents by itself once the network returns', () async {
    final network = _FakeNetwork(isAvailable: false);
    final sync = AutomaticSync(
      network: network,
      interval: const Duration(hours: 1),
    );
    addTearDown(sync.dispose);
    noNetwork();
    await sync.start();
    expect(ApiClient.offline.value, isTrue);

    await invoices().checkout(
      payload: invoice,
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    ApiClient.client = MockClient(
      (request) async => request.method == 'POST'
          ? json({
              'order': {'id': 51, 'invoice_number': 'INV-51'},
            }, 201)
          : json({'theme': 'blue'}),
    );
    network.change(true);
    await Future<void>.delayed(Duration.zero); // the network event arrives
    await sync.tick();

    final record = (await ApiClient.offlineStore!.operations()).single;
    expect(record['status'], 'confirmed');
    expect(ApiClient.offline.value, isFalse);
  });

  test('a document the server rejects during sync stays for review', () async {
    noNetwork();
    await invoices().checkout(
      payload: invoice,
      receiptItems: const [],
      cashierName: 'مندوب',
    );
    ApiClient.client = MockClient(
      (request) async => request.method == 'POST'
          ? json({'message': 'الكمية غير متوفرة'}, 422)
          : json({'theme': 'blue'}),
    );
    await SyncService.synchronize();
    final record = (await ApiClient.offlineStore!.operations()).single;
    expect(record['status'], 'rejected');
    expect(record['message'], 'الكمية غير متوفرة');
  });
}

class _FakeNetwork implements NetworkStatusSource {
  _FakeNetwork({required this.isAvailable});
  bool isAvailable;
  final _changes = StreamController<bool>.broadcast();

  void change(bool available) {
    isAvailable = available;
    _changes.add(available);
  }

  @override
  Future<bool> get available async => isAvailable;

  @override
  Stream<bool> get changes => _changes.stream;
}
