import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'api_config.dart';
import 'offline_store.dart';

/// Durable account-scoped operations. Uncertain writes are only queried.
class SyncService {
  static final busy = ValueNotifier<bool>(false);
  static final revision = ValueNotifier<int>(0);
  static bool _checkoutActive = false;
  static bool _automaticActive = false;
  static final lastError = ValueNotifier<String?>(null);
  static String? _errorToken;
  static String? get currentError =>
      _errorToken == ApiClient.token ? lastError.value : null;

  static Future<void> synchronizeAutomatically() async {
    if (_automaticActive ||
        busy.value ||
        _checkoutActive ||
        ApiClient.token == null ||
        ApiClient.sessionExpired.value) {
      return;
    }
    _automaticActive = true;
    final token = ApiClient.token;
    try {
      final pending = await pendingRecords();
      if (token != ApiClient.token || busy.value || _checkoutActive) return;
      if (pending.any(
        (record) =>
            const {'queued', 'sending', 'uncertain'}.contains(record['status']),
      )) {
        await _synchronize(pending);
      }
    } catch (error) {
      if (token == ApiClient.token) {
        _errorToken = token;
        lastError.value = _errorMessage(error);
      }
    } finally {
      _automaticActive = false;
    }
  }

  static String _errorMessage(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is http.ClientException || error is TimeoutException) {
      return 'تعذر الوصول إلى API على ${Uri.parse(ApiConfig.baseUrl).host}. ستُعاد محاولة المزامنة تلقائياً؛ لا تُرسل الفواتير غير المؤكدة مرة ثانية.';
    }
    return 'تعذرت المزامنة: $error';
  }

  static bool beginCheckout() {
    if (busy.value || _checkoutActive) return false;
    _checkoutActive = true;
    return true;
  }

  static void endCheckout() => _checkoutActive = false;

  static Future<void> synchronize() => _synchronize();

  static Future<void> _synchronize([
    List<Map<String, dynamic>>? snapshot,
  ]) async {
    if (busy.value) return;
    if (_checkoutActive) {
      throw StateError('انتظر اكتمال حفظ الفاتورة قبل المزامنة.');
    }
    final store = ApiClient.offlineStore;
    final token = ApiClient.token;
    if (store == null || token == null || ApiClient.sessionExpired.value) {
      throw StateError('سجّل الدخول بالحساب الذي حفظ العمليات أولاً.');
    }
    busy.value = true;
    _errorToken = token;
    lastError.value = null;
    var contactedServer = false;
    try {
      for (var record in snapshot ?? await store.pendingOperations()) {
        if (ApiClient.token != token || ApiClient.sessionExpired.value) break;
        if (const {
          'confirmed',
          'rejected',
          'verified_saved',
        }.contains(record['status'])) {
          continue;
        }
        final uuid = record['payload']['operation_uuid'];
        if (record['status'] != 'queued') {
          final check = await ApiClient.get(
            Uri.parse('${ApiConfig.baseUrl}/sale-operations/$uuid'),
          );
          if (check.statusCode == 200) {
            contactedServer = true;
            final data = jsonDecode(check.body);
            if (data['status'] == 'confirmed' &&
                data['result']?['order'] is Map) {
              await store.saveOperation({
                ...record,
                'status': 'confirmed',
                'order': data['result']['order'],
                'message': null,
              });
              continue;
            }
          }
          final message =
              'توجد فاتورة لم يتأكد حفظها على الخادم. تحتاج مراجعة؛ لم يُعد إرسالها. تُرسل بقية الفواتير التي لم تُرسل تلقائياً.';
          await store.saveOperation({...record, 'message': message});
          lastError.value = message;
          continue;
        }
        final shiftId = record['offline_shift_id'];
        if (shiftId == null) {
          throw StateError('عملية محلية بلا وردية معتمدة؛ تحتاج مراجعة.');
        }
        final shift = await ApiClient.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/shifts/active?branch_id=${record['payload']['branch_id']}',
          ),
        );
        if (shift.statusCode != 200) {
          throw StateError('تعذر التحقق من الوردية قبل المزامنة.');
        }
        contactedServer = true;
        if ('${jsonDecode(shift.body)['active_shift']?['id']}' != '$shiftId') {
          throw StateError(
            'الوردية الأصلية مغلقة أو تغيرت؛ راجع الفواتير المحلية قبل المزامنة.',
          );
        }
        if (ApiClient.token != token || ApiClient.sessionExpired.value) break;
        record = {...record, 'status': 'sending'};
        await store.saveOperation(record);
        final response = await ApiClient.post(
          Uri.parse('${ApiConfig.baseUrl}/${record['endpoint']}'),
          body: record['payload'],
        );
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          data = null;
        }
        if ((response.statusCode == 200 || response.statusCode == 201) &&
            data is Map &&
            data['order'] is Map &&
            data['order']['id'] != null) {
          await store.saveOperation({
            ...record,
            'status': 'confirmed',
            'order': data['order'],
            'message': null,
          });
        } else {
          final rejected =
              response.statusCode >= 400 &&
              response.statusCode < 500 &&
              !const {408, 409}.contains(response.statusCode);
          final errors = data is Map ? data['errors'] : null;
          final first = errors is Map && errors.isNotEmpty
              ? errors.values.first
              : null;
          final detail = first is List && first.isNotEmpty
              ? first.first
              : first;
          final message =
              (detail ??
                      (data is Map ? data['message'] : null) ??
                      'لم يصل تأكيد صالح')
                  .toString();
          await store.saveOperation({
            ...record,
            'status': rejected ? 'rejected' : 'uncertain',
            'message': message,
          });
          lastError.value = message;
          break;
        }
      }
      if (!contactedServer) {
        final response = await ApiClient.get(
          Uri.parse('${ApiConfig.baseUrl}/theme'),
        );
        if (response.statusCode != 200) {
          throw StateError('تعذر الاتصال بالخادم أو انتهت صلاحية الجلسة.');
        }
      }
      ApiClient.offline.value = false;
      ApiClient.cachedAt.value = null;
    } catch (error) {
      if (token == ApiClient.token) lastError.value = _errorMessage(error);
      rethrow;
    } finally {
      revision.value++;
      busy.value = false;
    }
  }

  static Future<List<Map<String, dynamic>>> records() async =>
      await ApiClient.offlineStore?.operations() ?? [];

  static Future<List<Map<String, dynamic>>> pendingRecords() async =>
      await ApiClient.offlineStore?.pendingOperations() ?? [];

  /// Used only after an explicit cashier check against the server ledger.
  static Future<void> resolveAfterVerification(
    String uuid, {
    required bool wasSaved,
  }) async {
    if (!beginCheckout()) throw StateError('انتظر اكتمال العملية الحالية.');
    try {
      final store = ApiClient.offlineStore;
      final record = await store?.operation(uuid);
      if (store == null || record == null) {
        throw StateError('تعذر العثور على العملية في هذا الحساب.');
      }
      if (!const {
        'sending',
        'uncertain',
        'rejected',
      }.contains(record['status'])) {
        return;
      }
      await store.saveOperation({
        ...record,
        'status': wasSaved ? 'verified_saved' : 'rejected',
        'message': wasSaved
            ? 'تحقق الكاشير يدويًا من حفظها على الخادم'
            : 'تحقق الكاشير يدويًا من عدم حفظها؛ لم يُعد إرسالها',
      });
      revision.value++;
    } finally {
      endCheckout();
    }
  }

  static Future<Map<String, dynamic>> enqueue({
    required OfflineStore store,
    required Map<String, dynamic> record,
    required String endpoint,
    required Object shiftId,
  }) async {
    final uuid = record['payload']['operation_uuid'] as String;
    final payload = record['payload'] as Map;
    final order = <String, dynamic>{
      ...payload,
      'id': 'local:$uuid',
      'invoice_number': await store.nextOfflineInvoiceNumber(),
      'created_at': record['created_at'],
      'status': 'queued',
      'offline_pending': true,
      'total': payload['total_amount'],
      'paid_amount': payload['total_amount'],
    };
    final queued = {
      ...record,
      'status': 'queued',
      'order': order,
      'endpoint': endpoint,
      'offline_shift_id': shiftId,
    };
    await store.saveOperation(queued);
    revision.value++;
    return queued;
  }
}
