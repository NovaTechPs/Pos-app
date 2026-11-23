import 'package:flutter/material.dart';

import '../services/sync_service.dart';

enum _StatusFilter { all, pending, posted }

/// Lists the invoices and receipts saved on this device and whether each one
/// reached the system, with the number the system gave it.
class InvoiceStatusScreen extends StatefulWidget {
  const InvoiceStatusScreen({super.key});

  @override
  State<InvoiceStatusScreen> createState() => _InvoiceStatusScreenState();
}

class _InvoiceStatusScreenState extends State<InvoiceStatusScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;
  _StatusFilter _filter = _StatusFilter.all;

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
      if (mounted) {
        setState(() {
          _records = records.reversed.toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر قراءة الفواتير المحفوظة على الجهاز.';
        });
      }
    }
  }

  Future<void> _sendNow() async {
    setState(() => _error = null);
    try {
      await SyncService.synchronize();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'تعذر الاتصال بالنظام؛ ستُرسل تلقائيًا عند عودة الاتصال.',
        );
      }
    }
    await _load();
  }

  static bool isPosted(Map<String, dynamic> record) =>
      const {'confirmed', 'verified_saved'}.contains(record['status']);

  static String documentType(Map<String, dynamic> record) =>
      switch (record['endpoint']) {
        'wholesale/receipts' => 'سند قبض',
        'wholesale/orders' => 'فاتورة جملة',
        _ => 'فاتورة مبيعات',
      };

  static String? serverNumber(Map<String, dynamic> record) {
    if (record['status'] != 'confirmed') return null;
    final order = record['order'];
    if (order is! Map) return null;
    final number = order['voucher_number'] ?? order['invoice_number'];
    return number == null ? null : '$number';
  }

  static String? localNumber(Map<String, dynamic> record) {
    final saved = record['local_number'];
    if (saved != null) return '$saved';
    if (record['status'] == 'confirmed') return null;
    final order = record['order'];
    final number = order is Map
        ? order['voucher_number'] ?? order['invoice_number']
        : null;
    return number == null ? null : '$number';
  }

  static String _date(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (parsed == null) return '';
    String two(int part) => part.toString().padLeft(2, '0');
    return '${parsed.year}/${two(parsed.month)}/${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static String _amount(Map<String, dynamic> record) {
    final order = record['order'] is Map ? record['order'] as Map : const {};
    final payload = record['payload'] is Map
        ? record['payload'] as Map
        : const {};
    final value = num.tryParse(
      '${order['total'] ?? order['amount'] ?? payload['total_amount'] ?? payload['amount'] ?? ''}',
    );
    return value == null ? '' : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _records.where((record) => !isPosted(record)).length;
    final posted = _records.length - pending;
    final visible = _records
        .where(
          (record) => switch (_filter) {
            _StatusFilter.all => true,
            _StatusFilter.pending => !isPosted(record),
            _StatusFilter.posted => isPosted(record),
          },
        )
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_StatusFilter>(
                  segments: [
                    ButtonSegment(
                      value: _StatusFilter.all,
                      label: Text('الكل (${_records.length})'),
                    ),
                    ButtonSegment(
                      value: _StatusFilter.pending,
                      label: Text('لم تُرحّل ($pending)'),
                    ),
                    ButtonSegment(
                      value: _StatusFilter.posted,
                      label: Text('مرحّلة ($posted)'),
                    ),
                  ],
                  selected: {_filter},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.single),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<bool>(
                  valueListenable: SyncService.busy,
                  builder: (_, busy, _) => FilledButton.icon(
                    key: const Key('send-pending-documents'),
                    onPressed: busy || pending == 0 ? null : _sendNow,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      busy ? 'جارٍ الإرسال…' : 'ترحيل غير المرحّلة الآن',
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _records.isEmpty
                          ? 'لا توجد فواتير محفوظة على هذا الجهاز دون إنترنت.'
                          : 'لا توجد فواتير بهذه الحالة.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: visible.length,
                    itemBuilder: (_, index) => _tile(visible[index], colors),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> record, ColorScheme colors) {
    final type = documentType(record);

    final server = serverNumber(record);
    final local = localNumber(record);
    final (
      String status,
      Color color,
      IconData icon,
    ) = switch (record['status']) {
      'confirmed' => (
        server == null ? 'مرحّلة' : 'مرحّلة — $type رقم $server على النظام',
        Colors.green.shade700,
        Icons.cloud_done_outlined,
      ),
      'verified_saved' => (
        'مرحّلة (تحقق يدوي)',
        Colors.green.shade700,
        Icons.cloud_done_outlined,
      ),
      'rejected' => (
        'لم تُرحّل — رفضها النظام${record['message'] == null ? '' : ': ${record['message']}'}',
        colors.error,
        Icons.error_outline,
      ),
      'queued' => (
        'لم تُرحّل — بانتظار الاتصال',
        Colors.orange.shade800,
        Icons.cloud_upload_outlined,
      ),
      _ => (
        'لم تُرحّل — جارٍ التحقق من النظام',
        Colors.orange.shade800,
        Icons.cloud_sync_outlined,
      ),
    };
    final customer = record['customer_name'];
    final details = [
      if (customer != null && '$customer'.isNotEmpty) '$customer',
      if (_amount(record).isNotEmpty) 'المبلغ ${_amount(record)}',
      _date(record['created_at']),
    ].where((part) => part.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        isThreeLine: true,
        leading: Icon(icon, color: color),
        title: Text(local == null ? type : '$type $local'),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: status,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              TextSpan(text: '\n$details'),
            ],
          ),
        ),
      ),
    );
  }
}
