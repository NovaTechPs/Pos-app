import 'package:flutter/material.dart';

import '../models/sale_data.dart';
import '../services/pos_service.dart';
import '../services/api_client.dart';
import '../services/printer_service.dart';

class InvoiceBrowser extends StatefulWidget {
  const InvoiceBrowser({
    super.key,
    required this.order,
    required this.branchId,
    required this.onViewed,
  });
  final Map<String, dynamic> order;
  final int branchId;
  final ValueChanged<Map<String, dynamic>> onViewed;

  @override
  State<InvoiceBrowser> createState() => _InvoiceBrowserState();
}

class _InvoiceBrowserState extends State<InvoiceBrowser> {
  late Map<String, dynamic> _order = widget.order;
  bool _busy = false;
  String? _error;

  Future<void> _navigate(bool next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = SaleData.id(_order['id']);
      final order = await PosService().fetchInvoice(
        widget.branchId,
        before: next ? null : id,
        after: next ? id : null,
      );
      if (!mounted) return;
      setState(() => _order = order);
      widget.onViewed(order);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'لا توجد فاتورة ${next ? 'أحدث' : 'أقدم'} متاحة.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print({bool pdf = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = SaleData.heldLines(_order);
      SaleData.applyOffers(items);
      if (pdf) {
        await PrinterService.shareReceipt(
          order: _order,
          items: items,
          cashierName: '—',
        );
      } else {
        await PrinterService.printReceipt(
          order: _order,
          items: items,
          cashierName: '—',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذرت الطباعة أو مشاركة الفاتورة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text('${_order['invoice_number'] ?? _order['id']}')),
        IconButton(
          onPressed: _busy ? null : () => _navigate(false),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'السابقة',
        ),
        IconButton(
          onPressed: _busy ? null : () => _navigate(true),
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'التالية',
        ),
      ],
    ),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              'العميل: ${_order['party']?['name'] ?? _order['customer_name'] ?? 'عميل نقدي'}',
            ),
            Text('التاريخ: ${_order['created_at'] ?? '—'}'),
            for (final raw in _order['items'] as List? ?? [])
              ListTile(
                title: Text(
                  '${raw['product']?['name'] ?? raw['name'] ?? 'منتج'}${raw['is_gift'] == true ? ' — هدية' : ''}',
                ),
                subtitle: Text('${raw['quantity']} × ${raw['unit_price']}'),
                trailing: Text('${raw['total_price']}'),
              ),
            Text('الخصم: ${_order['discount'] ?? 0}'),
            Text('الإجمالي: ${_order['total']}'),
            if (_order['notes'] != null) Text('ملاحظات: ${_order['notes']}'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _print(pdf: true),
        child: const Text('PDF'),
      ),
      TextButton(onPressed: _busy ? null : _print, child: const Text('طباعة')),
      TextButton(
        onPressed: _busy || ApiClient.offline.value
            ? null
            : () =>
                  Navigator.pop(context, {'action': 'delete', 'order': _order}),
        child: const Text('حذف الفاتورة'),
      ),
      FilledButton(
        onPressed: _busy || ApiClient.offline.value
            ? null
            : () => Navigator.pop(context, {'action': 'edit', 'order': _order}),
        child: const Text('تعديل الفاتورة'),
      ),
    ],
  );
}
