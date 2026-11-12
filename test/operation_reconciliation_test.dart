import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/checkout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ApiClient.client.close());

  Future<CheckoutService> uncertain({String resultKey = 'order'}) async {
    final service = CheckoutService(
      scope: 'reconcile-test',
      resultKey: resultKey,
      send: (_) async => throw TimeoutException('response lost'),
    );
    await service.checkout(
      payload: {'branch_id': 1, 'total_amount': 20},
      receiptItems: [],
      cashierName: 'Cashier',
    );
    expect(CheckoutService.needsReview(await service.read()), isTrue);
    return service;
  }

  test(
    'positive server lookup resolves a lost response without another write',
    () async {
      final service = await uncertain();
      final before = await service.read();
      ApiClient.client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          endsWith('/sale-operations/${before?['payload']['operation_uuid']}'),
        );
        return http.Response(
          jsonEncode({
            'status': 'confirmed',
            'result': {
              'order': {'id': 42, 'total': 20},
            },
          }),
          200,
        );
      });
      expect(await service.reconcile(), isTrue);
      expect((await service.read())?['order']['id'], 42);
      expect((await service.read())?['status'], 'confirmed');
    },
  );
  test('missing lookup result never authorizes resubmission', () async {
    final service = await uncertain();
    ApiClient.client = MockClient((_) async => http.Response('{}', 404));
    expect(await service.reconcile(), isFalse);
    expect(CheckoutService.needsReview(await service.read()), isTrue);
    final blocked = await service.checkout(
      payload: {},
      receiptItems: [],
      cashierName: 'Cashier',
    );
    expect(blocked['needs_review'], isTrue);
  });
  test('return journals reconcile using the return API response key', () async {
    final service = await uncertain(resultKey: 'return_order');
    ApiClient.client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'confirmed',
          'result': {
            'return_order': {'id': 7, 'total': -20},
          },
        }),
        200,
      ),
    );
    expect(await service.reconcile(), isTrue);
    expect((await service.read())?['order']['id'], 7);
  });
}
