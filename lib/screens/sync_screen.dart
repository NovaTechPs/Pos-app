import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';
import '../services/api_config.dart';
import '../services/pos_service.dart';
import '../services/customer_service.dart';
import '../services/shift_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<Map<String, dynamic>> _records = [];
  String? _error;
  bool _loading = true;
  bool _preparing = false;
  String? _preparationMessage;
  String _offlineReadiness = 'جارٍ التحقق من بيانات العمل دون اتصال…';
  int get _branchId => int.tryParse('${ApiClient.user?['branch_id']}') ?? 0;
  @override
  void initState() {
    super.initState();
    SyncService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final records = await SyncService.records();
      final store = ApiClient.offlineStore;
      final hasCatalog =
          await store?.hasCached(
            Uri.parse(
              '${ApiConfig.baseUrl}/pos/products?branch_id=$_branchId',
            ),
          ) ??
          false;
      final shift = await store?.cached(
        Uri.parse('${ApiConfig.baseUrl}/shifts/active?branch_id=$_branchId'),
      );
      final shiftData = shift == null
          ? null
          : jsonDecode(shift['body'] as String);
      final readiness = !hasCatalog
          ? 'لم تُنزّل بيانات البيع على هذا الجهاز بعد.'
          : shiftData?['active_shift']?['id'] == null
          ? 'الأصناف محفوظة، ويلزم فتح وردية أثناء الاتصال وتنزيل بياناتها.'
          : 'توجد أصناف ووردية محفوظة تدعم البيع دون اتصال. استخدم زر التجهيز لتحديثها.';
      if (mounted) {
        setState(() {
          _records = records.reversed.toList();
          _offlineReadiness = readiness;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر قراءة السجل المحلي؛ لم تُحذف أي عملية.';
        });
      }
    }
  }

  Future<void> _sync() async {
    setState(() => _error = null);
    try {
      await SyncService.synchronize();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    await _load();
  }

  Future<void> _prepareOffline() async {
    if (_preparing || SyncService.busy.value) return;
    setState(() {
      _preparing = true;
      _error = null;
      _preparationMessage = null;
    });
    final token = ApiClient.token;
    try {
      if (_branchId <= 0 || token == null) {
        throw StateError('سجّل الدخول واختر الفرع أولاً.');
      }
      final products = PosService();
      final customers = CustomerService();
      final shifts = ShiftService();
      final results = await Future.wait<dynamic>([
        products.fetchCategories(_branchId),
        customers.fetchCustomers(),
        shifts.fetchActiveShift(_branchId),
      ]);
      if (ApiClient.token != token || ApiClient.sessionExpired.value) {
        throw StateError('تغيّرت الجلسة؛ أعد تسجيل الدخول ثم جهّز البيانات.');
      }
      if (products.lastFetchOffline ||
          customers.lastFetchOffline ||
          shifts.lastFetchOffline) {
        final stale = [
          if (products.lastFetchOffline) 'الأصناف',
          if (customers.lastFetchOffline) 'العملاء',
          if (shifts.lastFetchOffline) 'الوردية',
        ].join('، ');
        throw StateError(
          'تعذر تنزيل بيانات حديثة من الخادم: $stale. لم يصل رد خلال المهلة أو انقطع الاتصال بالخادم. البيانات السابقة باقية؛ أعد المحاولة.',
        );
      }
      ApiClient.offline.value = false;
      ApiClient.cachedAt.value = null;
      if (results[2] == null) {
        throw StateError(
          'افتح وردية أثناء الاتصال بالإنترنت، ثم اضغط التجهيز مجدداً.',
        );
      }
      await products.prepareOfflineCustomerPricing(
        _branchId,
        results[1] as List,
      );
      if (mounted && ApiClient.token == token) {
        setState(
          () => _preparationMessage = 'نُزّلت الأصناف والعملاء والوردية المفتوحة. يمكنك الآن البيع دون اتصال باستخدام البيانات المحفوظة.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
      await _load();
    }
  }

  Future<void> _print(Map<String, dynamic> record) async {
    try {
      await PrinterService.printReceipt(
        order: {
          ...Map<String, dynamic>.from(record['order']),
          'offline_rejected': record['status'] == 'rejected',
        },
        items: (record['items'] as List).map((line) {
          final item = Map<String, dynamic>.from(line);
          item['price'] =
              (item['price'] as num) - (item['discount'] as num? ?? 0);
          return item;
        }).toList(),
        cashierName: '${record['cashier_name']}',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذرت الطباعة؛ السجل المحلي محفوظ.');
      }
    }
  }

  Future<void> _review(Map<String, dynamic> record) async {
    final wasSaved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('التحقق اليدوي من الفاتورة'),
        content: Text(
          'راجع سجل فواتير الخادم والمبلغ والأصناف قبل اختيار النتيجة. هذا الإجراء لا يعيد إرسال الفاتورة.\nمعرف العملية: ${record['payload']['operation_uuid']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تحققت: لم تُحفظ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تحققت: محفوظة على الخادم'),
          ),
        ],
      ),
    );
    if (wasSaved == null) return;
    try {
      await SyncService.resolveAfterVerification(
        '${record['payload']['operation_uuid']}',
        wasSaved: wasSaved,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المزامنة والفواتير المحلية')),
    body: Column(
      children: [
        Flexible(
          flex: 2,
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'الفواتير المحلية محفوظة على هذا الجهاز. تُرسل بالحساب والفرع والوردية الأصلية عند المزامنة.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'الخادم: ${ApiConfig.baseUrl}',
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 6),
                  Text(_offlineReadiness),
                  ValueListenableBuilder<String?>(
                    valueListenable: SyncService.lastError,
                    builder: (context, _, _) => SyncService.currentError == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: const Key('automatic-sync-error'),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              SyncService.currentError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: SyncService.busy,
                    builder: (_, busy, _) => OutlinedButton.icon(
                      key: const Key('prepare-offline'),
                      onPressed:
                          _preparing || busy || ApiClient.sessionExpired.value
                          ? null
                          : _prepareOffline,
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: Text(
                        _preparing
                            ? 'جارٍ تنزيل البيانات والتحقق من الخادم…'
                            : 'تجهيز العمل دون اتصال',
                      ),
                    ),
                  ),
                  if (_preparationMessage != null) Text(_preparationMessage!),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<bool>(
                    valueListenable: SyncService.busy,
                    builder: (_, busy, _) => FilledButton.icon(
                      onPressed:
                          busy || _preparing || ApiClient.sessionExpired.value
                          ? null
                          : _sync,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        busy ? 'جارٍ التحقق والمزامنة…' : 'مزامنة الآن',
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _records.isEmpty
              ? const Center(child: Text('لا توجد فواتير محلية محفوظة'))
              : ListView.builder(
                  itemCount: _records.length,
                  itemBuilder: (_, index) {
                    final record = _records[index];
                    final status = switch (record['status']) {
                      'confirmed' => 'تمت المزامنة',
                      'verified_saved' =>
                        'تم التحقق يدويًا من حفظها — راجع رقم فاتورة الخادم',
                      'queued' => 'محفوظة محليًا — بانتظار المزامنة',
                      'rejected' => 'غير معتمدة على الخادم — تحتاج مراجعة',
                      _ => 'لم يتأكد الإرسال — التحقق فقط',
                    };
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        isThreeLine: true,
                        leading: Icon(
                          record['status'] == 'confirmed'
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_upload_outlined,
                        ),
                        title: Text(
                          '${record['order']?['invoice_number'] ?? record['payload']['operation_uuid']}',
                        ),
                        subtitle: Text(
                          '$status\n${record['created_at']} · ${record['payload']['total_amount']} ${record['message'] ?? ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (const {
                              'sending',
                              'uncertain',
                              'rejected',
                            }.contains(record['status']))
                              IconButton(
                                onPressed: () => _review(record),
                                icon: const Icon(Icons.fact_check_outlined),
                                tooltip: 'التحقق اليدوي',
                              ),
                            IconButton(
                              onPressed: () => _print(record),
                              icon: const Icon(Icons.print_outlined),
                              tooltip: 'طباعة الفاتورة',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
