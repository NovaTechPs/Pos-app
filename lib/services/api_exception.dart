import 'dart:convert';

import 'background_json.dart';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;

  static Map<String, dynamic> decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(
        'وصل رد غير صالح من الخادم. حاول التحديث لاحقاً.',
        statusCode: response.statusCode,
      );
    }
    return _check(response, decoded);
  }

  /// Like [decode], but parses large bodies (full catalogs, customer lists)
  /// on a background isolate so the UI keeps rendering and scanning.
  static Future<Map<String, dynamic>> decodeAsync(
    http.Response response,
  ) async {
    dynamic decoded;
    try {
      decoded = await BackgroundJson.decodeBytes(response.bodyBytes);
    } catch (_) {
      throw ApiException(
        'وصل رد غير صالح من الخادم. حاول التحديث لاحقاً.',
        statusCode: response.statusCode,
      );
    }
    return _check(response, decoded);
  }

  static Map<String, dynamic> _check(http.Response response, dynamic decoded) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final fallback = switch (response.statusCode) {
        401 => 'انتهت الجلسة. سجّل الدخول مجدداً.',
        403 => 'ليست لديك صلاحية لتنفيذ هذه العملية.',
        422 => 'تحقق من البيانات المدخلة.',
        _ => 'تعذر إتمام الطلب (${response.statusCode}).',
      };
      final errors = decoded is Map ? decoded['errors'] : null;
      final first = errors is Map && errors.isNotEmpty
          ? errors.values.first
          : null;
      final detail = first is List && first.isNotEmpty ? first.first : first;
      throw ApiException(
        response.statusCode == 401 || response.statusCode == 403
            ? fallback
            : (detail ??
                      (decoded is Map ? decoded['message'] : null) ??
                      fallback)
                  .toString(),
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw const ApiException('صيغة بيانات الخادم غير متوقعة.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
