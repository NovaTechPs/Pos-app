import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/screens/sync_screen.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/pos_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
    await ApiClient.saveSession(
      token: 'test-token',
      session: {
        'user': {'id': 1, 'tenant_id': 1, 'branch_id': 1},
      },
    );
  });
  tearDown(() => ApiClient.client.close());

  http.Response response(Map<String, dynamic> data) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  testWidgets('slow reachable catalog replaces stale data during preparation', (
    tester,
  ) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=1');
    await ApiClient.offlineStore!.cache(uri, jsonEncode({'categories': []}));
    ApiClient.offline.value = true;
    ApiClient.client = MockClient((request) async {
      if (request.url.path.endsWith('/pos/products')) {
        await Future<void>.delayed(const Duration(seconds: 6));
        return response({
          'categories': [
            {'id': 99, 'name': 'جديد', 'products': []},
          ],
        });
      }
      if (request.url.path.endsWith('/customers')) {
        return response({'customers': []});
      }
      return response({
        'active_shift': {'id': 7},
      });
    });
    await tester.pumpWidget(const MaterialApp(home: SyncScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-offline')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    // Preparation also saves a pricing snapshot from a second catalog read.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('يمكنك الآن البيع دون اتصال'), findsOneWidget);
    expect(find.textContaining('تعذر تنزيل بيانات حديثة'), findsNothing);
    final cached = await ApiClient.offlineStore!.cached(uri);
    expect(jsonDecode(cached!['body'] as String)['categories'][0]['id'], 99);
    expect(ApiClient.offline.value, false);
    expect(tester.takeException(), isNull);
  });

  test('offline pricing reuses a fresh catalog but never another session catalog', () async {
    var downloads = 0;
    ApiClient.client = MockClient((_) async {
      downloads++;
      return response({
        'categories': [
          {'id': downloads, 'products': []},
        ],
      });
    });
    final service = PosService();
    await service.fetchCategories(1);
    await service.prepareOfflineCustomerPricing(1, []);
    expect(downloads, 1);
    final pricing = Uri.parse(
      '${ApiConfig.baseUrl}/pos/offline-pricing?branch_id=1&pricing_branch_id=1',
    );
    expect(await ApiClient.offlineStore!.cached(pricing), isNotNull);
    await service.fetchCategories(1);
    await ApiClient.saveSession(
      token: 'other-token',
      session: {
        'user': {'id': 2, 'tenant_id': 1, 'branch_id': 1},
      },
    );
    await service.prepareOfflineCustomerPricing(1, []);
    expect(downloads, 3);
    final cached = await ApiClient.offlineStore!.cached(pricing);
    expect(jsonDecode(cached!['body'] as String)['categories'][0]['id'], 3);
  });

  for (final supported in [false, true]) {
    testWidgets(
      'offline preparation works with contract flag=$supported without sending sales',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var writes = 0;
        ApiClient.client = MockClient((request) async {
          if (request.method != 'GET') writes++;
          if (request.url.path.endsWith('/pos/products')) {
            return response({
              'categories': [],
              if (supported) 'offline_contract_version': 1,
            });
          }
          if (request.url.path.endsWith('/customers')) {
            return response({'customers': []});
          }
          return response({
            'active_shift': {'id': 7},
            if (supported) 'offline_contract_version': 1,
          });
        });
        await ApiClient.offlineStore!.saveDraft(1, {'notes': 'مسودة محفوظة'});
        await tester.pumpWidget(const MaterialApp(home: SyncScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prepare-offline')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('يمكنك الآن البيع دون اتصال'),
          findsOneWidget,
        );
        expect(writes, 0);
        expect(
          (await ApiClient.offlineStore!.draft(1))!['notes'],
          'مسودة محفوظة',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cached success cannot claim preparation succeeded without a connection',
    (tester) async {
      await ApiClient.offlineStore!.cache(
        Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=1'),
        jsonEncode({'categories': [], 'offline_contract_version': 1}),
      );
      await ApiClient.offlineStore!.cache(
        Uri.parse('${ApiConfig.baseUrl}/customers'),
        jsonEncode({'customers': []}),
      );
      await ApiClient.offlineStore!.cache(
        Uri.parse('${ApiConfig.baseUrl}/shifts/active?branch_id=1'),
        jsonEncode({
          'active_shift': {'id': 7},
          'offline_contract_version': 1,
        }),
      );
      ApiClient.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      await tester.pumpWidget(const MaterialApp(home: SyncScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prepare-offline')));
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذر تنزيل بيانات حديثة'), findsOneWidget);
      expect(find.textContaining('يمكنك الآن البيع دون اتصال'), findsNothing);
      expect(ApiClient.offline.value, true);
      expect(tester.takeException(), isNull);
    },
  );
}
