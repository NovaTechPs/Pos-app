import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_exception.dart';
import 'package:waslapos_app/services/customer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
  });
  tearDown(() => ApiClient.client.close());

  for (final nested in [false, true]) {
    test('loads customers beyond the first seven, nested: $nested', () async {
      final pages = <int>[];
      ApiClient.client = MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        pages.add(page);
        final rows = List.generate(
          7,
          (i) => {
            'id': (page - 1) * 7 + i + 1,
            'name': 'Customer ${(page - 1) * 7 + i + 1}',
          },
        );
        final pagination = {'current_page': page, 'last_page': 3};
        return http.Response(
          jsonEncode({
            'parties': nested ? {'data': rows, ...pagination} : rows,
            if (!nested) 'meta': pagination,
          }),
          200,
        );
      });
      final result = await CustomerService().fetchWholesaleParties();
      expect(result.length, 21);
      expect(result.last['id'], 21);
      expect(pages, [1, 2, 3]);
    });
  }

  test('follows next links and removes repeated party IDs', () async {
    ApiClient.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'parties': [
            {'id': 1},
            if (request.url.hasQuery) {'id': 2},
          ],
          'next_page_url': request.url.hasQuery ? null : '?page=2',
        }),
        200,
      ),
    );
    expect((await CustomerService().fetchWholesaleParties()).length, 2);
  });

  test('rejects foreign pagination links without requesting them', () async {
    var calls = 0;
    ApiClient.client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'parties': [
            {'id': 1},
          ],
          'next_page_url': 'https://example.org/wholesale/parties?page=2',
        }),
        200,
      );
    });
    await expectLater(
      CustomerService().fetchWholesaleParties(),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });

  test('does not return an incomplete list when a later page fails', () async {
    ApiClient.client = MockClient(
      (request) async => request.url.hasQuery
          ? http.Response('{}', 500)
          : http.Response(
              jsonEncode({
                'parties': [
                  {'id': 1},
                ],
                'next_page_url': '?page=2',
              }),
              200,
            ),
    );
    await expectLater(
      CustomerService().fetchWholesaleParties(),
      throwsA(isA<ApiException>()),
    );
  });
}
