import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_config.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String? code,
  }) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/login'),
        body: {
          'email': email,
          'password': password,
          if (code != null && code.isNotEmpty) 'code': code,
        },
        authenticated: false,
      );
      final data = Map<String, dynamic>.from(jsonDecode(response.body));

      if (response.statusCode == 200 && data['token'] is String) {
        final session = {
          'user': data['user'],
          'employee': data['employee'],
          'today_attendance': data['today_attendance'],
        };
        await ApiClient.saveSession(token: data['token'], session: session);
        return {
          'success': true,
          'user': data['user'],
          'employee': data['employee'],
          'today_attendance': data['today_attendance'],
          'message': data['message'],
        };
      }
      return {
        'success': false,
        'message': _messageFrom(data) ?? 'تعذر تسجيل الدخول',
      };
    } catch (error) {
      debugPrint('Login request failed: $error');
      return {'success': false, 'message': 'تعذر الاتصال بالخادم'};
    }
  }

  Future<void> logout() async {
    try {
      await ApiClient.post(Uri.parse('$baseUrl/logout'));
    } finally {
      await ApiClient.clearSession();
    }
  }

  String? _messageFrom(Map<String, dynamic> data) {
    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty) return message;
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }
    return null;
  }
}
