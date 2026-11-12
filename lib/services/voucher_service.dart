import 'dart:convert';

import 'api_config.dart';

import 'api_client.dart';

class VoucherService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> createReceipt({
    required int branchId,
    int? customerId,
    required double amount,
    String? notes,
  }) async {
    try {
      final Map<String, dynamic> payload = {
        'branch_id': branchId,
        'amount': amount,
        'notes': notes,
      };

      if (customerId != null) {
        payload['customer_id'] = customerId;
      }

      final response = await ApiClient.post(
        Uri.parse('$baseUrl/vouchers/receipts'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'voucher': data['voucher'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل إصدار سند القبض',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
