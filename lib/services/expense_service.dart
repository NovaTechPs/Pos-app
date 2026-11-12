import 'dart:convert';

import 'api_config.dart';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

class ExpenseService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<List<dynamic>> fetchExpenses(int branchId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('$baseUrl/expenses?branch_id=$branchId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['expenses'] ?? [];
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching expenses: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createExpense({
    required int branchId,
    required double amount,
    String? notes,
  }) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/expenses'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'branch_id': branchId,
          'amount': amount,
          'notes': notes,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'expense': data['expense'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل تسجيل المصروف',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
