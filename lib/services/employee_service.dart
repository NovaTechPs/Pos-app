import 'dart:convert';

import 'api_config.dart';

import 'api_client.dart';
import 'api_exception.dart';

class EmployeeService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/employee/profile'),
    );
    return ApiException.decode(response);
  }

  Future<Map<String, dynamic>> clock({required String type}) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/employee/attendance/clock'),
        body: {'type': type},
      );
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'تعذر تسجيل الحركة',
        'attendance': data['attendance'],
      };
    } catch (error) {
      return {'success': false, 'message': 'تعذر الاتصال بالخادم: $error'};
    }
  }

  Future<Map<String, dynamic>> scanAttendance({
    required String employeeCode,
  }) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/employee/attendance/scan'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'employee_code': employeeCode}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'type': data['type'],
          'employee': data['employee'],
          'attendance': data['attendance'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل تسجيل الحضور',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchFinances() async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/employee/finances'),
      headers: {'Accept': 'application/json'},
    );
    return ApiException.decode(response);
  }

  Future<Map<String, dynamic>> submitRequest(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/employee/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 201,
        'message': data['message'] ?? 'تعذر إرسال الطلب',
      };
    } catch (e) {
      return {'success': false, 'message': 'تعذر الاتصال: $e'};
    }
  }
}
