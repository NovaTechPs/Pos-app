import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:waslapos_app/services/checkout_service.dart';

class BrokenStorage extends FlutterSecureStorage {
  BrokenStorage({this.afterFirst = false});
  final bool afterFirst;
  int writes = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (afterFirst && writes++ == 0) {
      return super.write(key: key, value: value);
    }
    throw PlatformException(code: 'storage_unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final payload = <String, dynamic>{
    'branch_id': 1,
    'total_amount': 20,
    'items': [
      {'product_id': 2, 'quantity': 2, 'price': 10},
    ],
  };
  final items = <Map<String, dynamic>>[
    {
      'product_id': 2,
      'name': 'منتج',
      'quantity': 2,
      'price': 10,
      'discount': 0,
    },
  ];
  Future<Map<String, dynamic>> sell(CheckoutService service) =>
      service.checkout(
        payload: payload,
        receiptItems: items,
        cashierName: 'Cashier',
        heldOrderId: 7,
      );
  http.Response success() => http.Response(
    jsonEncode({
      'order': {'id': 42, 'invoice_number': 'INV-42', 'total': 20},
    }),
    201,
  );

  test(
    'writes before sending and restores a confirmed receipt in a new instance',
    () async {
      late CheckoutService service;
      service = CheckoutService(
        scope: 'test',
        send: (_) async {
          final record = await service.read();
          expect(record!['status'], 'sending');
          expect(
            record['payload'],
            containsPair('total_amount', payload['total_amount']),
          );
          expect(record['payload']['held_order_id'], 7);
          expect(
            record['payload']['operation_uuid'],
            matches(RegExp(r'^[0-9a-f-]{36}$')),
          );
          return success();
        },
      );
      expect((await sell(service))['success'], true);
      final restored = await CheckoutService(scope: 'test').read();
      expect(restored!['status'], 'confirmed');
      expect(restored['order']['id'], 42);
      expect(restored['items'], items);
      expect(restored['held_order_id'], 7);
    },
  );

  test('concurrent clicks send only one request', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final service = CheckoutService(
      scope: 'test',
      send: (_) {
        calls++;
        return response.future;
      },
    );
    final first = sell(service);
    expect((await sell(service))['success'], false);
    response.complete(success());
    expect((await first)['success'], true);
    expect(calls, 1);
  });

  test('accepts a successful 200 response without manual review', () async {
    final service = CheckoutService(
      scope: 'test',
      send: (_) async => http.Response(success().body, 200),
      lookup: (_) async => throw StateError('lookup must not run'),
    );
    expect((await sell(service))['success'], true);
    expect((await service.read())?['status'], 'confirmed');
  });

  for (final lostResponse in [true, false]) {
    test(
      'automatically confirms ${lostResponse ? 'timeout' : 'gateway error'} using original UUID',
      () async {
        var sends = 0;
        String? sentUuid;
        final service = CheckoutService(
          scope: 'test',
          send: (payload) async {
            sends++;
            sentUuid = payload['operation_uuid'];
            if (lostResponse) throw TimeoutException('lost response');
            return http.Response('gateway error', 502);
          },
          lookup: (uuid) async {
            expect(uuid, sentUuid);
            return http.Response(
              jsonEncode({
                'status': 'confirmed',
                'result': jsonDecode(success().body),
              }),
              200,
            );
          },
        );
        final result = await sell(service);
        expect(result['success'], true);
        expect(result['order']['id'], 42);
        expect(sends, 1);
        expect((await service.read())?['status'], 'confirmed');
      },
    );
  }

  test(
    'missing automatic confirmation keeps the sale locked without resending',
    () async {
      var sends = 0;
      final service = CheckoutService(
        scope: 'test',
        send: (_) async {
          sends++;
          throw TimeoutException('lost response');
        },
        lookup: (_) async => http.Response('{}', 404),
      );
      expect((await sell(service))['needs_review'], true);
      expect((await sell(service))['needs_review'], true);
      expect(sends, 1);
    },
  );

  test(
    'timeout survives restart and prevents automatic resubmission',
    () async {
      final service = CheckoutService(
        scope: 'test',
        send: (_) async {
          throw TimeoutException('Lost confirmation');
        },
      );
      expect((await sell(service))['needs_review'], true);
      var calls = 0;
      final restarted = CheckoutService(
        scope: 'test',
        send: (_) async {
          calls++;
          return success();
        },
      );
      expect(CheckoutService.needsReview(await restarted.read()), true);
      expect((await sell(restarted))['needs_review'], true);
      expect(calls, 0);
      await restarted.resolveAfterVerification(wasSaved: false);
      expect((await sell(restarted))['success'], true);
      expect(calls, 1);
    },
  );

  for (final code in [201, 408, 409, 500, 502]) {
    test('malformed response $code remains unresolved', () async {
      final service = CheckoutService(
        scope: 'test',
        send: (_) async => http.Response('<html>gateway error</html>', code),
      );
      expect((await sell(service))['needs_review'], true);
      expect(CheckoutService.needsReview(await service.read()), true);
    });
  }

  test(
    'validation rejection retains receipt lines and permits corrected sale',
    () async {
      var calls = 0;
      final service = CheckoutService(
        scope: 'test',
        send: (_) async {
          calls++;
          return calls == 1
              ? http.Response('{"message":"Invalid payment"}', 422)
              : success();
        },
      );
      final result = await sell(service);
      expect(result['success'], false);
      expect(result['needs_review'], false);
      expect((await service.read())!['items'], items);
      expect((await sell(service))['success'], true);
    },
  );

  test('failed local persistence prevents the HTTP request', () async {
    var calls = 0;
    final service = CheckoutService(
      scope: 'test',
      storage: BrokenStorage(),
      send: (_) async {
        calls++;
        return success();
      },
    );
    expect((await sell(service))['success'], false);
    expect(calls, 0);
  });

  test('records are isolated by cashier and branch scope', () async {
    final a = CheckoutService(
      scope: 'cashier-a|branch-1',
      send: (_) async => success(),
    );
    await sell(a);
    expect(await CheckoutService(scope: 'cashier-b|branch-1').read(), isNull);
    expect(await CheckoutService(scope: 'cashier-a|branch-2').read(), isNull);
  });

  test(
    'server success remains success when storing confirmation fails',
    () async {
      final service = CheckoutService(
        scope: 'test',
        storage: BrokenStorage(afterFirst: true),
        send: (_) async => success(),
      );
      final result = await sell(service);
      expect(result['success'], true);
      expect(result['local_save_failed'], true);
      expect(result['order']['id'], 42);
      // The durable pre-send record still blocks a duplicate after restart.
      expect(
        CheckoutService.needsReview(
          await CheckoutService(scope: 'test').read(),
        ),
        true,
      );
    },
  );

  test('a corrupted journal never results in a new HTTP request', () async {
    FlutterSecureStorage.setMockInitialValues({
      'wasla_checkout_test': '{broken',
    });
    var calls = 0;
    final service = CheckoutService(
      scope: 'test',
      send: (_) async {
        calls++;
        return success();
      },
    );
    expect((await sell(service))['success'], false);
    expect(calls, 0);
  });
}
