import 'package:flutter/material.dart';

import '../models/sale_data.dart';
import '../services/return_service.dart';
import '../services/checkout_service.dart';
import '../widgets/operation_review.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key, required this.user, required this.branchId});
  final Map<String, dynamic> user;
  final int branchId;
  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final _invoice = TextEditingController();
  final _reason = TextEditingController();
  final _service = ReturnService();
  late final CheckoutService _journal;
  final Map<int, TextEditingController> _quantities = {};
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _record;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _journal = _service.journal(widget.branchId);
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final record = await _journal.read();
      if (mounted) setState(() => _record = record);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر قراءة سجل المرتجع المحلي.');
    }
  }

  void _clearQuantities() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _quantities.clear();
  }

  @override
  void dispose() {
    _invoice.dispose();
    _reason.dispose();
    _clearQuantities();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || _invoice.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final order = await _service.findInvoice(_invoice.text.trim());
      if (!mounted) return;
      if (order != null && SaleData.id(order['branch_id']) != widget.branchId) {
        throw Exception(
          'هذه الفاتورة تتبع فرعاً آخر. افتح فرع الفاتورة أولاً.',
        );
      }
      _clearQuantities();
      for (final line in (order?['items'] as List? ?? [])) {
        final id = SaleData.id(line['id']);
        if (id != null) _quantities[id] = TextEditingController(text: '0');
      }
      setState(() {
        _order = order;
        if (order == null) _error = 'لم يتم العثور على الفاتورة.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await reviewOperation(context, _journal);
      if (!mounted) return;
      await _loadRecord();
      if (saved != null && mounted) {
        setState(() {
          _order = null;
          _message = saved
              ? 'تم تأكيد حفظ المرتجع السابق.'
              : 'تم تسجيل نتيجة المراجعة؛ ابحث عن الفاتورة مجدداً.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<dynamic> get _lines => _order?['items'] as List? ?? [];
  double get _preview => _lines.fold<double>(0, (total, line) {
    final quantity =
        SaleData.number(_quantities[SaleData.id(line['id'])]?.text) ?? 0;
    return total +
        quantity *
            (SaleData.number(line['refund_unit_price'] ?? line['unit_price']) ??
                0);
  });

  Future<void> _submit() async {
    if (_busy || _order == null || CheckoutService.needsReview(_record)) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final items = <Map<String, dynamic>>[];
      double subtotal = 0;
      for (final line in _lines) {
        final quantity = SaleData.number(
          _quantities[SaleData.id(line['id'])]?.text,
        );
        final available = SaleData.number(line['remaining_quantity']) ?? 0;
        final price = SaleData.number(line['unit_price']);
        if (quantity == null ||
            price == null ||
            quantity < 0 ||
            quantity > available) {
          throw Exception('أدخل كمية صحيحة لا تتجاوز المتبقي من الفاتورة.');
        }
        if (quantity == 0) continue;
        subtotal += quantity * price;
        items.add({
          'product_id': line['product_id'],
          'original_order_item_id': line['id'],
          'quantity': quantity,
          'price': price,
        });
      }
      if (items.isEmpty) throw Exception('اختر كمية لصنف واحد على الأقل.');
      final result = await _journal.checkout(
        payload: {
          'branch_id': widget.branchId,
          'original_order_id': _order!['id'],
          'items': items,
          'subtotal': subtotal,
          'total_amount': double.parse(_preview.toStringAsFixed(2)),
          'reason': _reason.text.trim(),
        },
        receiptItems: items,
        cashierName: widget.user['name']?.toString() ?? 'كاشير',
      );
      await _loadRecord();
      if (!mounted) return;
      if (result['success'] == true) {
        final order = result['order'];
        setState(() {
          _order = null;
          _message =
              'تم حفظ المرتجع ${order['invoice_number']}. قيمة المرتجع: ${order['total']}، والمبلغ المسترد: ${order['paid_amount']}';
        });
      } else {
        setState(
          () => _error = result['message']?.toString() ?? 'تعذر حفظ المرتجع.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('مرتجعات المبيعات')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (CheckoutService.needsReview(_record))
              Card(
                child: ListTile(
                  title: const Text('مرتجع سابق يحتاج التحقق'),
                  subtitle: const Text(
                    'لن يُرسل مرتجع جديد حتى مراجعة النتيجة.',
                  ),
                  trailing: TextButton(
                    onPressed: _review,
                    child: const Text('تحقق'),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_message != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_message!),
                ),
              ),
            TextField(
              controller: _invoice,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الفاتورة الأصلية',
                prefixIcon: Icon(Icons.receipt_long),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _search,
              child: const Text('البحث عن الفاتورة'),
            ),
            if (_order != null) ...[
              const SizedBox(height: 20),
              Text('العميل: ${_order!['party']?['name'] ?? 'عميل نقدي'}'),
              const Text(
                'أدخل الكمية المراد إرجاعها فقط. السعر يشمل نصيب الصنف من خصم الفاتورة.',
              ),
              ..._lines.map(
                (line) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          line['product']?['name'] ?? 'منتج',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'المتبقي: ${line['remaining_quantity'] ?? 0} • قيمة الوحدة المستردة: ${line['refund_unit_price'] ?? line['unit_price']}',
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _quantities[SaleData.id(line['id'])],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'كمية المرتجع',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'سبب المرتجع'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Text('القيمة التقديرية: ${_preview.toStringAsFixed(2)} ر.س'),
              const Text(
                'يحدد الخادم المبلغ المسترد نقداً وتخفيض المديونية بناءً على مدفوعات الفاتورة.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: CheckoutService.needsReview(_record)
                    ? null
                    : _submit,
                icon: const Icon(Icons.assignment_return),
                label: const Text('تأكيد المرتجع'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
