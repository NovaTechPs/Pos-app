import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/dashboard_service.dart';
import 'package:waslapos_app/services/shift_service.dart';
import 'package:waslapos_app/services/api_exception.dart';
import 'package:waslapos_app/services/auth_service.dart';
import 'package:waslapos_app/services/sales_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
  });
  tearDown(() => ApiClient.client.close());

  test('confirmed writes renew connectivity only for their authenticated session and branch', () async {
    await ApiClient.saveSession(
      token: 'secret',
      session: {
        'user': {'id': 7, 'tenant_id': 1, 'branch_id': 2},
      },
    );
    final uri = Uri.parse('${ApiConfig.baseUrl}/pos/orders');
    ApiClient.client = MockClient(
      (_) async => http.Response('{"order":{"id":1}}', 201),
    );
    expect(ApiClient.hasRecentConnection(3), isFalse);
    await ApiClient.post(uri, body: {'branch_id': 3});
    expect(ApiClient.hasRecentConnection(3), isTrue);
    expect(ApiClient.hasRecentConnection(2), isFalse);
    ApiClient.client = MockClient((_) async => http.Response('{}', 422));
    await ApiClient.post(uri, body: {'branch_id': 3});
    expect(ApiClient.hasRecentConnection(3), isFalse);
    ApiClient.client = MockClient((_) async => http.Response('{}', 201));
    await ApiClient.post(uri, body: {'branch_id': 3}, authenticated: false);
    expect(ApiClient.hasRecentConnection(3), isFalse);
    await ApiClient.post(
      Uri.parse('https://example.com/orders'),
      body: {'branch_id': 3},
    );
    expect(ApiClient.hasRecentConnection(3), isFalse);
    await ApiClient.post(uri, body: '{"branch_id":3}');
    expect(ApiClient.hasRecentConnection(3), isTrue);
    ApiClient.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    await expectLater(
      ApiClient.post(uri, body: {'branch_id': 3}),
      throwsA(isA<http.ClientException>()),
    );
    expect(ApiClient.hasRecentConnection(3), isFalse);
  });

  test('recent connection requires a real successful read in the same session and branch', () async {
    Future<void> login() => ApiClient.saveSession(
      token: 'secret',
      session: {
        'user': {'id': 7, 'tenant_id': 1, 'branch_id': 2},
      },
    );
    await login();
    final uri = Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=2');
    ApiClient.client = MockClient((_) async => http.Response('{}', 200));
    await ApiClient.get(uri, cacheForOffline: true);
    expect(ApiClient.hasRecentConnection(2), isTrue);
    expect(ApiClient.hasRecentConnection(3), isFalse);
    await login();
    expect(ApiClient.hasRecentConnection(2), isFalse);
    await ApiClient.get(uri, cacheForOffline: true, preferCache: true);
    expect(ApiClient.hasRecentConnection(2), isFalse);
    await ApiClient.get(uri);
    expect(ApiClient.hasRecentConnection(2), isTrue);
    ApiClient.client = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    await ApiClient.get(uri, cacheForOffline: true);
    expect(ApiClient.hasRecentConnection(2), isFalse);
  });

  test(
    'corrupt persisted sessions recover to login without failing bootstrap',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'wasla_session_v2': '{broken',
      });
      await ApiClient.initialize();
      expect(ApiClient.user, isNull);
      expect(ApiClient.initializationError, isNotNull);
    },
  );
  test('session envelope is restored with its matching token', () async {
    await ApiClient.saveSession(
      token: 'secret',
      session: {
        'user': {'id': 7, 'tenant_id': 1},
      },
    );
    await ApiClient.initialize();
    expect(ApiClient.token, 'secret');
    expect(ApiClient.user?['id'], 7);
  });
  test(
    'explicit offline logout removes the saved session across restart',
    () async {
      await ApiClient.saveSession(
        token: 'saved-session',
        session: {
          'user': {'id': 7, 'tenant_id': 1, 'branch_id': 2},
        },
      );
      ApiClient.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        AuthService().logout(),
        throwsA(isA<http.ClientException>()),
      );
      expect(ApiClient.user, isNull);
      expect(ApiClient.token, isNull);
      await ApiClient.initialize();
      expect(ApiClient.user, isNull);
      expect(ApiClient.token, isNull);
    },
  );
  test('body branch is used for both map and JSON string writes', () async {
    await ApiClient.saveSession(
      token: 'secret',
      session: {
        'user': {'id': 7, 'tenant_id': 1, 'branch_id': 2},
      },
    );
    ApiClient.client = MockClient((request) async {
      expect(request.headers['X-Branch-ID'], '3');
      expect(request.headers['X-Tenant-ID'], '1');
      expect(request.headers['Authorization'], 'Bearer secret');
      return http.Response('{}', 200);
    });
    await ApiClient.post(
      Uri.parse('https://example.test/api/write'),
      body: {'branch_id': 3},
    );
    await ApiClient.post(
      Uri.parse('https://example.test/api/write'),
      body: jsonEncode({'branch_id': 3}),
    );
  });
  test('unauthorized requests notify once and never retry writes', () async {
    await ApiClient.saveSession(
      token: 'secret',
      session: {
        'user': {'id': 7},
      },
    );
    int calls = 0;
    ApiClient.client = MockClient((_) async {
      calls++;
      return http.Response('{}', 401);
    });
    final response = await ApiClient.post(
      Uri.parse('https://example.test/api/write'),
      body: {},
    );
    expect(response.statusCode, 401);
    expect(ApiClient.sessionExpired.value, isTrue);
    expect(calls, 1);
  });
  test(
    'failed report and shift requests never masquerade as empty data',
    () async {
      ApiClient.client = MockClient(
        (_) async => http.Response('{"message":"failed"}', 503),
      );
      await expectLater(
        DashboardService().fetchSummary(1),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        ShiftService().fetchActiveShift(1),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('history applies branch pagination search and dates to the real API contract', () async {
    ApiClient.client = MockClient((request) async {
      expect(request.url.path, '/api/wholesale/orders');
      expect(request.url.queryParameters, containsPair('branch_id', '3'));
      expect(request.url.queryParameters, containsPair('page', '2'));
      expect(request.url.queryParameters, containsPair('search', 'INV-1'));
      expect(request.url.queryParameters, containsPair('from', '2026-10-01'));
      return http.Response('{"orders":{"data":[],"last_page":2}}', 200);
    });
    final result = await SalesHistoryService().fetch(
      branchId: 3,
      wholesale: true,
      page: 2,
      search: ' INV-1 ',
      from: '2026-10-01',
    );
    expect(result['last_page'], 2);
  });
}
