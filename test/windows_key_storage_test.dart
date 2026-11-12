import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/checkout_service.dart';
import 'package:waslapos_app/services/windows_key_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const options = <String, String>{};
  late Directory directory;
  final workers = <WindowsKeyStorage>[];
  Future<WindowsKeyStorage> open() async {
    final storage = await WindowsKeyStorage.open(directory.path);
    workers.add(storage);
    return storage;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wasla-storage-test-');
  });
  tearDown(() async {
    for (final worker in workers) {
      await worker.close();
    }
    workers.clear();
    await directory.delete(recursive: true);
  });

  test('the real secure-storage facade persists confirmed and uncertain checkouts across restart', () async {
    final previous = FlutterSecureStoragePlatform.instance;
    try {
      FlutterSecureStoragePlatform.instance = await open();
      await ApiClient.saveSession(
        token: 'native-token',
        session: {
          'user': {'id': 1, 'tenant_id': 1, 'branch_id': 1},
        },
      );
      final checkout = CheckoutService(
        scope: 'native-sale',
        send: (_) async =>
            http.Response('{"order":{"id":42,"invoice_number":"42"}}', 201),
      );
      final result = await checkout.checkout(
        payload: {'branch_id': 1, 'items': []},
        receiptItems: [],
        cashierName: 'Cashier',
      );
      expect(result['success'], isTrue);
      FlutterSecureStoragePlatform.instance = await open();
      await ApiClient.initialize();
      expect(ApiClient.token, 'native-token');
      expect(
        (await CheckoutService(scope: 'native-sale').read())?['order']['id'],
        42,
      );
      var posts = 0;
      final uncertain = CheckoutService(
        scope: 'native-uncertain',
        lookup: (_) async => http.Response('{}', 404),
        send: (_) async {
          posts++;
          throw const FormatException('interrupted response');
        },
      );
      expect(
        (await uncertain.checkout(
          payload: {'branch_id': 1, 'items': []},
          receiptItems: [],
          cashierName: 'Cashier',
        ))['success'],
        isFalse,
      );
      expect(posts, 1);
      FlutterSecureStoragePlatform.instance = await open();
      expect(
        CheckoutService.needsReview(
          await CheckoutService(scope: 'native-uncertain').read(),
        ),
        isTrue,
      );
    } finally {
      FlutterSecureStoragePlatform.instance = previous;
    }
  }, skip: !Platform.isWindows);

  test('legacy sessions, offline invoices and catalog survive encrypted per-key writes and restart', () async {
    final legacy = File('${directory.path}/flutter_secure_storage.dat');
    final original = windowsProtect(
      utf8.encode(
        jsonEncode({
          'session': 'secret-token',
          'operation_1': '{"status":"queued"}',
          'catalog': 'large saved catalog',
          'deleted': 'old value',
        }),
      ),
    );
    await legacy.writeAsBytes(original, flush: true);
    final storage = await open();
    expect(
      await storage.read(key: 'session', options: options),
      'secret-token',
    );
    expect(
      await storage.read(key: 'operation_1', options: options),
      contains('queued'),
    );
    await storage.write(
      key: 'operation_1',
      value: '{"status":"confirmed"}',
      options: options,
    );
    await storage.delete(key: 'deleted', options: options);
    final restarted = await open();
    expect(
      await restarted.read(key: 'operation_1', options: options),
      contains('confirmed'),
    );
    expect(
      await restarted.containsKey(key: 'deleted', options: options),
      isFalse,
    );
    expect(await restarted.readAll(options: options), {
      'session': 'secret-token',
      'operation_1': '{"status":"confirmed"}',
      'catalog': 'large saved catalog',
    });
    expect(await legacy.readAsBytes(), original);
    final files = await Directory('${directory.path}/wasla_secure_records_v1')
        .list()
        .toList();
    for (final entry in files.whereType<File>()) {
      expect(
        utf8.decode(await entry.readAsBytes(), allowMalformed: true),
        isNot(contains('confirmed')),
      );
    }
    await restarted.deleteAll(options: options);
    expect(await restarted.readAll(options: options), isEmpty);
    final afterClear = await open();
    expect(await afterClear.readAll(options: options), isEmpty);
  }, skip: !Platform.isWindows);

  test('parallel writes stay durable and corrupt financial data is never deleted or replaced by legacy', () async {
    final storage = await open();
    await Future.wait(
      List.generate(
        30,
        (i) => storage.write(
          key: 'invoice-$i',
          value: 'queued-$i',
          options: options,
        ),
      ),
    );
    expect(await storage.readAll(options: options), hasLength(30));
    final file = File(
      '${directory.path}/wasla_secure_records_v1/${sha256.convert(utf8.encode('invoice-0'))}.dat',
    );
    await file.writeAsString('corrupt', flush: true);
    await expectLater(
      storage.read(key: 'invoice-0', options: options),
      throwsStateError,
    );
    expect(await file.readAsString(), 'corrupt');
    expect(await storage.read(key: 'invoice-1', options: options), 'queued-1');
  }, skip: !Platform.isWindows);

  test('large catalog never gets rewritten by draft or checkout saves and UI timers keep running', () async {
    final storage = await open();
    final catalog = List.filled(24 * 1024 * 1024, 'x').join();
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 2),
      (_) => ticks++,
    );
    await storage.write(key: 'catalog', value: catalog, options: options);
    heartbeat.cancel();
    expect(ticks, greaterThan(0));
    final file = File(
      '${directory.path}/wasla_secure_records_v1/${sha256.convert(utf8.encode('catalog'))}.dat',
    );
    final before = await file.stat();
    final timer = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await storage.write(
        key: 'checkout',
        value: 'invoice-$i',
        options: options,
      );
      expect(
        await storage.read(key: 'checkout', options: options),
        'invoice-$i',
      );
    }
    final after = await file.stat();
    expect(after.modified, before.modified);
    expect(after.size, before.size);
    // Informational timings, not a hardware-dependent pass/fail threshold.
    // ignore: avoid_print
    print(
      '24MB catalog: ten durable checkout writes+reads ${timer.elapsedMilliseconds}ms; UI timer ticks=$ticks',
    );
  }, skip: !Platform.isWindows);
}
