import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'api_config.dart';
import 'operation_id.dart';
import 'sync_service.dart';

typedef CheckoutSender = Future<http.Response> Function(
  Map<String, dynamic> payload,
);

/// A write-ahead record protects against blindly repeating an unconfirmed sale.
/// Server-side idempotency is still required for automatic retries.
class CheckoutService {
  CheckoutService({
    required String scope,
    this.storage = const FlutterSecureStorage(),
    this.resultKey = 'order',
    this.offlineEndpoint,
    this.requireOfflineShift = true,
    CheckoutSender? send,
    this.lookup,
  }) : _key = 'wasla_checkout_${Uri.encodeComponent(scope)}',
       _send = send ?? _submit;

  final String _key;
  final String resultKey;
  final String? offlineEndpoint;

  /// POS sales stay tied to the shift they were sold in; sales invoices and
  /// receipts are attached to whichever shift is open when they reach the server.
  final bool requireOfflineShift;
  final FlutterSecureStorage storage;
  final CheckoutSender _send;
  final Future<http.Response> Function(String uuid)? lookup;
  bool _busy = false;
  final Stopwatch _probeAge = Stopwatch();
  String? _probeToken;
  Object? _probeBranch;

  static Future<http.Response> _submit(Map<String, dynamic> payload) =>
      ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/pos/orders'),
        body: payload,
      );

  Future<Map<String, dynamic>?> read() async {
    final value = await storage.read(key: _key);
    if (value == null) return null;
    final record = Map<String, dynamic>.from(jsonDecode(value));
    final uuid = record['payload']?['operation_uuid'];
    if (offlineEndpoint != null && uuid is String) {
      final queued = await ApiClient.offlineStore?.operation(uuid);
      if (queued != null) return queued;
    }
    return record;
  }

  Future<void> _write(Map<String, dynamic> record) =>
      storage.write(key: _key, value: jsonEncode(record));

  Future<void> _saveReview(Map<String, dynamic> record) async {
    final store = ApiClient.offlineStore;
    final uuid = record['payload']?['operation_uuid'];
    if (offlineEndpoint != null &&
        store != null &&
        uuid is String &&
        await store.operation(uuid) != null) {
      await store.saveOperation(record);
      SyncService.revision.value++;
    }
    await _write(record);
  }

  static bool needsReview(Map<String, dynamic>? record) =>
      record != null &&
      const {'sending', 'uncertain'}.contains(record['status']);

  // Query the original UUID only; an absent result never permits another POST.
  Future<Map<String, dynamic>?> _confirmAutomatically(
    Map<String, dynamic> record,
    String? sessionToken,
  ) async {
    if (lookup == null && sessionToken == null) return null;
    try {
      final uuid = record['payload']['operation_uuid'] as String;
      final response =
          await (lookup != null
                  ? lookup!(uuid)
                  : ApiClient.get(
                      Uri.parse('${ApiConfig.baseUrl}/sale-operations/$uuid'),
                    ))
              .timeout(const Duration(seconds: 4));
      if (ApiClient.token != sessionToken || ApiClient.sessionExpired.value) {
        return null;
      }
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final order = data['result']?[resultKey];
      if (data['status'] != 'confirmed' ||
          order is! Map ||
          order['id'] == null) {
        return null;
      }
      var localSaveFailed = false;
      try {
        await _saveReview({...record, 'status': 'confirmed', 'order': order});
      } catch (_) {
        localSaveFailed = true;
      }
      return {
        'success': true,
        'order': Map<String, dynamic>.from(order),
        'local_save_failed': localSaveFailed,
      };
    } catch (_) {
      return null;
    }
  }

  /// A missing result is not proof of failure: the original request may still run.
  Future<bool> reconcile() async {
    if (_busy || !SyncService.beginCheckout()) return false;
    _busy = true;
    try {
      final record = await read();
      if (!needsReview(record)) return record?['status'] == 'confirmed';
      final uuid = record?['payload']?['operation_uuid'];
      if (uuid == null) return false;
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/sale-operations/$uuid'),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      final order = data['result']?[resultKey];
      if (data['status'] != 'confirmed' ||
          order is! Map ||
          order['id'] == null) {
        return false;
      }
      await _saveReview({...record!, 'status': 'confirmed', 'order': order});
      return true;
    } finally {
      _busy = false;
      SyncService.endCheckout();
    }
  }

  /// Only call after the cashier checks the order against the server's records.
  Future<void> resolveAfterVerification({required bool wasSaved}) async {
    if (_busy || !SyncService.beginCheckout()) {
      throw StateError('Checkout is still running');
    }
    try {
      final record = await read();
      if (!needsReview(record)) return;
      await _saveReview({
        ...record!,
        'status': wasSaved ? 'verified_saved' : 'rejected',
      });
    } finally {
      SyncService.endCheckout();
    }
  }

  Future<Map<String, dynamic>> checkout({
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> receiptItems,
    required String cashierName,
    int? heldOrderId,
    Object? offlineShiftId,
    bool probeWhenOffline = false,
  }) async {
    if (_busy || !SyncService.beginCheckout()) {
      return {
        'success': false,
        'message': 'عملية البيع أو المزامنة قيد التنفيذ',
      };
    }
    _busy = true;
    final sessionToken = ApiClient.token;
    Map<String, dynamic>? record;
    var sent = false;
    final timer = Stopwatch()..start();
    var stage = 'local_record';
    try {
      if (needsReview(await read())) {
        return {
          'success': false,
          'needs_review': true,
          'message': 'راجع العملية السابقة في سجل المبيعات قبل إعادة الإرسال',
        };
      }
      // Reuse a recent reachability check; the financial endpoint still validates
      // each sale. Offline events, session changes and branch changes bypass it.
      final recentProbe =
          ApiClient.hasRecentConnection(payload['branch_id']) ||
          (!ApiClient.offline.value &&
              _probeAge.isRunning &&
              _probeAge.elapsed < const Duration(seconds: 15) &&
              _probeToken == sessionToken &&
              _probeBranch == payload['branch_id']);
      if (offlineEndpoint != null &&
          !recentProbe &&
          (!ApiClient.offline.value || probeWhenOffline)) {
        try {
          final probe = await ApiClient.get(
            Uri.parse(
              '${ApiConfig.baseUrl}/shifts/active?branch_id=${payload['branch_id']}',
            ),
            timeout: const Duration(seconds: 3),
          );
          if (probe.statusCode < 200 || probe.statusCode >= 300) {
            return {
              'success': false,
              'message':
                  'تعذر التحقق من الجلسة والوردية. احتُفظ بالفاتورة للمراجعة.',
            };
          }
          ApiClient.offline.value = probe.headers['x-wasla-offline'] == 'true';
          if (!ApiClient.offline.value) {
            ApiClient.cachedAt.value = null;
            _probeToken = sessionToken;
            _probeBranch = payload['branch_id'];
            _probeAge
              ..reset()
              ..start();
          }
        } catch (error) {
          if (error is! http.ClientException && error is! TimeoutException) {
            rethrow;
          }
          ApiClient.offline.value = true;
          _probeAge.stop();
        }
      }
      final useOffline = offlineEndpoint != null && ApiClient.offline.value;
      if (useOffline &&
          (payload['invoice_id'] != null || payload['receipt_id'] != null)) {
        return {
          'success': false,
          'message': 'تعديل مستند محفوظ يحتاج اتصالًا بالإنترنت. يمكنك حفظ مستند جديد دون إنترنت.',
        };
      }
      if (ApiClient.offline.value && offlineEndpoint == null) {
        return {
          'success': false,
          'message':
              'هذه العملية تتطلب الاتصال بالخادم حاليًا. لم تُرسل أي بيانات.',
        };
      }
      // JSON cloning also freezes receipt lines while the screen is busy.
      record = Map<String, dynamic>.from(
        jsonDecode(
          jsonEncode({
            'status': 'sending',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'payload': {
              ...payload,
              'operation_uuid': OperationId.create(),
              'held_order_id': ?heldOrderId,
              if (useOffline && offlineShiftId != null)
                'offline_shift_id': offlineShiftId,
            },
            'items': receiptItems,
            'cashier_name': cashierName,
            'held_order_id': heldOrderId,
          }),
        ),
      );
      await _write(record); // Never send a sale without a durable local record.
      if (ApiClient.token != sessionToken || ApiClient.sessionExpired.value) {
        await _write({...record, 'status': 'rejected'});
        return {
          'success': false,
          'message': 'تغيّرت الجلسة؛ لم تُرسل الفاتورة.',
        };
      }
      if (useOffline) {
        final store = ApiClient.offlineStore;
        if (store == null ||
            (requireOfflineShift && offlineShiftId == null) ||
            ApiClient.sessionExpired.value) {
          await _write({...record, 'status': 'rejected'});
          return {
            'success': false,
            'message': 'يلزم حساب محفوظ ووردية معتمدة للبيع دون إنترنت.',
          };
        }
        final queued = await SyncService.enqueue(
          store: store,
          record: record,
          endpoint: offlineEndpoint!,
          shiftId: offlineShiftId,
          resultKey: resultKey,
          requiresShift: requireOfflineShift,
        );
        try {
          await _write(queued);
        } catch (_) {
          /* read() recovers from outbox. */
        }
        return {'success': true, 'queued': true, 'order': queued['order']};
      }
      sent = true;
      stage = 'server_response';
      final response = await _send(
        Map<String, dynamic>.from(record['payload']),
      );
      developer.log(
        'POST status=${response.statusCode} elapsed_ms=${timer.elapsedMilliseconds}',
        name: 'waslapos.checkout',
      );
      record = {
        ...record,
        'response_status': response.statusCode,
        'response_elapsed_ms': timer.elapsedMilliseconds,
      };
      stage = 'confirmation';
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } on FormatException {
        // A gateway can return HTML even after the server commits the order.
      }
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data?[resultKey] is Map &&
          (data![resultKey]['id'] != null ||
              data[resultKey]['invoice_number'] != null)) {
        final order = Map<String, dynamic>.from(data[resultKey]);
        record = {...record, 'status': 'confirmed', 'order': order};
        var localSaveFailed = false;
        try {
          await _write(record);
        } catch (_) {
          localSaveFailed = true;
        }
        return {
          'success': true,
          'order': order,
          'local_save_failed': localSaveFailed,
        };
      }
      final rejected =
          response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 408 &&
          response.statusCode != 409;
      if (!rejected) {
        final confirmed = await _confirmAutomatically(record, sessionToken);
        if (confirmed != null) return confirmed;
      }
      record = {...record, 'status': rejected ? 'rejected' : 'uncertain'};
      await _write(record);
      return {
        'success': false,
        'needs_review': !rejected,
        'message': rejected
            ? (data?['message']?.toString() ??
                  'رفض الخادم الطلب؛ احتُفظ بالسلة')
            : 'لم يتأكد حفظ الفاتورة. راجع سجل المبيعات قبل إعادة الإرسال',
      };
    } catch (error) {
      developer.log(
        'stage=$stage elapsed_ms=${timer.elapsedMilliseconds} error_type=${error.runtimeType}',
        name: 'waslapos.checkout',
      );
      if (sent && record != null) {
        final confirmed = await _confirmAutomatically(record, sessionToken);
        if (confirmed != null) return confirmed;
      }
      // The original 'sending' record deliberately survives a timeout or crash.
      return {
        'success': false,
        'needs_review': sent,
        'message': sent
            ? 'انقطع تأكيد العملية. راجع سجل المبيعات قبل إعادة الإرسال'
            : 'تعذر حفظ سجل العملية محلياً؛ لم تُرسل الفاتورة',
      };
    } finally {
      _busy = false;
      SyncService.endCheckout();
    }
  }
}
