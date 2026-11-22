import 'dart:convert';

import 'api_config.dart';

import 'api_exception.dart';

import 'api_client.dart';

class CustomerService {
  bool lastFetchOffline = false;
  static String get baseUrl => ApiConfig.baseUrl;

  Future<List<dynamic>> fetchCustomers({bool preferCache = false}) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/customers'),
      cacheForOffline: true,
      preferCache: preferCache,
    );
    final data = await ApiException.decodeAsync(response);
    lastFetchOffline = response.headers['x-wasla-offline'] == 'true';
    if (data['customers'] is! List) {
      throw const ApiException('تعذر قراءة العملاء.');
    }
    return data['customers'];
  }

  Future<List<dynamic>> fetchWholesaleParties() async {
    final endpoint = Uri.parse('$baseUrl/wholesale/parties');
    Uri? next = endpoint;
    final visited = <String>{};
    final parties = <dynamic>[];
    final ids = <String>{};
    lastFetchOffline = false;
    while (next != null) {
      if (next.origin != endpoint.origin ||
          next.path != endpoint.path ||
          !visited.add(next.toString())) {
        throw const ApiException('تعذر تحميل بقية الزبائن والموردين.');
      }
      final response = await ApiClient.get(
        next,
        cacheForOffline: true,
        preferCache: ApiClient.offline.value,
        savedCopyTimeout: ApiClient.savedCopyWait,
      );
      final data = await ApiException.decodeAsync(response);
      lastFetchOffline |= response.headers['x-wasla-offline'] == 'true';
      final payload = data['parties'];
      final rows = payload is Map ? payload['data'] : payload;
      if (rows is! List ||
          rows.any((row) => row is! Map || row['id'] == null)) {
        throw const ApiException('تعذر قراءة الزبائن والموردين.');
      }
      for (final row in rows) {
        if (ids.add('${row['id']}')) parties.add(row);
      }
      final page = payload is Map ? payload : data;
      final meta = page['meta'] is Map ? page['meta'] as Map : page;
      final links = page['links'];
      final nextUrl =
          page['next_page_url'] ?? (links is Map ? links['next'] : null);
      final current = int.tryParse('${meta['current_page']}');
      final last = int.tryParse('${meta['last_page']}');
      if (nextUrl is String && nextUrl.isNotEmpty) {
        next = next.resolve(nextUrl);
      } else if (current != null && last != null && current < last) {
        next = next.replace(
          queryParameters: {...next.queryParameters, 'page': '${current + 1}'},
        );
      } else {
        next = null;
      }
    }
    return parties;
  }

  Future<Map<String, dynamic>> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? taxNumber,
    String? address,
  }) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/customers'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'email': email,
          'tax_number': taxNumber,
          'address': address,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'customer': data['customer'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل إضافة العميل',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
