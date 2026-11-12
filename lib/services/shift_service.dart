import 'dart:convert';

import 'api_config.dart';

import 'api_exception.dart';

import 'api_client.dart';
import 'sync_service.dart';

class ShiftService {
  bool lastFetchOffline = false;
  bool supportsOfflineSales = false;
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>?> fetchActiveShift(
    int branchId, {
    bool preferCache = false,
  }) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/shifts/active?branch_id=$branchId'),
      cacheForOffline: true,
      preferCache: preferCache,
    );
    final data = ApiException.decode(response);
    lastFetchOffline = response.headers['x-wasla-offline'] == 'true';
    supportsOfflineSales = data['offline_contract_version'] == 1;
    if (!data.containsKey('active_shift')) {
      throw const ApiException('تعذر التحقق من حالة الوردية.');
    }
    final shift = data['active_shift'];
    return shift == null ? null : Map<String, dynamic>.from(shift);
  }

  Future<Map<String, dynamic>> openShift({
    required int branchId,
    required double openingCash,
    String? notes,
  }) async {
    if (ApiClient.offline.value) {
      return {
        'success': false,
        'message': 'اتصل بالخادم لفتح وردية جديدة؛ يمكنك متابعة الوردية المحفوظة دون اتصال.',
      };
    }
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/shifts/open'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'branch_id': branchId,
          'opening_cash': openingCash,
          'notes': notes,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await ApiClient.offlineStore?.forget(
          Uri.parse('$baseUrl/shifts/active?branch_id=$branchId'),
        );
        return {
          'success': true,
          'shift': data['shift'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل فتح الوردية',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  Future<Map<String, dynamic>> closeShift({
    required int shiftId,
    required double actualCash,
    double? expectedCash,
    String? notes,
    int? branchId,
  }) async {
    try {
      if (ApiClient.offline.value ||
          (await SyncService.records()).any(
            (record) =>
                const {
                  'queued',
                  'sending',
                  'uncertain',
                }.contains(record['status']) &&
                '${record['offline_shift_id']}' == '$shiftId',
          )) {
        return {
          'success': false,
          'message': 'زامن الفواتير المحلية وراجع العمليات غير المؤكدة قبل إغلاق الوردية.',
        };
      }
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/shifts/close'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'shift_id': shiftId,
          'actual_cash': actualCash,
          'expected_cash': ?expectedCash,
          'notes': notes,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final branch = branchId ?? ApiClient.user?['branch_id'];
        await ApiClient.offlineStore?.forget(
          Uri.parse('$baseUrl/shifts/active?branch_id=$branch'),
        );
        return {
          'success': true,
          'shift': data['shift'],
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'فشل إغلاق الوردية',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }
}
