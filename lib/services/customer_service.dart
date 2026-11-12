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
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/wholesale/parties'),
      cacheForOffline: true,
    );
    final data = await ApiException.decodeAsync(response);
    if (data['parties'] is! List) {
      throw const ApiException('تعذر قراءة الزبائن والموردين.');
    }
    return data['parties'];
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
