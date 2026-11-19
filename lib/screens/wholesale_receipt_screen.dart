import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/checkout_service.dart';
import '../services/customer_service.dart';
import '../services/wholesale_service.dart';
import '../services/printer_service.dart';
import '../models/sale_data.dart';
import '../models/payment_summary.dart';
import '../widgets/payment_confirmation.dart';
import '../widgets/customer_picker.dart';
import '../widgets/operation_review.dart';

class WholesaleReceiptScreen extends StatefulWidget {
  const WholesaleReceiptScreen({
    super.key,
    required this.user,
    this.customers = const [],
    this.initialCustomerId,
  });
  final Map<String, dynamic> user;
  final List<dynamic> customers;
  final int? initialCustomerId;
  @override
  State<WholesaleReceiptScreen> createState() => _WholesaleReceiptScreenState();
}

class _WholesaleReceiptScreenState extends State<WholesaleReceiptScreen> {
  final _service = WholesaleService();
  final _customerService = CustomerService();
  final _amount = TextEditingController(), _notes = TextEditingController();
  late final CheckoutService _checkout;
  final List<dynamic> _customers = [];
  int? _customerId;
  Map<String, dynamic>? _voucher, _record;
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _busy = true, _editing = false;
  int get branch => SaleData.id(widget.user['branch_id']) ?? 0;
  bool get _readOnly => _voucher != null && !_editing;
  bool get _locked =>
      _busy || _readOnly || CheckoutService.needsReview(_record);
  double n(Object? value) => SaleData.number(value) ?? 0;
  String money(Object? value) => n(value).toStringAsFixed(2);
  Map? get _customer => _customers
      .cast<Map>()
      .where((r) => SaleData.id(r['id']) == _customerId)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    _customers.addAll(
      widget.customers.map((row) => Map<String, dynamic>.from(row)).toList(),
    );
    if (_customers.any(
      (row) => SaleData.id(row['id']) == widget.initialCustomerId,
    )) {
      _customerId = widget.initialCustomerId;
    }
    _checkout = CheckoutService(
      scope: [
        ApiConfig.baseUrl,
        widget.user['tenant_id'],
        widget.user['id'],
        branch,
        'wholesale-receipt',
      ].join('|'),
      resultKey: 'voucher',
      send: (payload) => ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/wholesale/receipts'),
        body: payload,
      ),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      _record = await _checkout.read();
    } catch (e) {
      _message(e);
    }
    try {
      final customers = await _customerService.fetchWholesaleParties();
      if (mounted) {
        _customers
          ..clear()
          ..addAll(
            customers.map((row) => Map<String, dynamic>.from(row)).toList(),
          );
      }
    } catch (e) {
      if (_customers.isEmpty) {
        _message('تعذر تحميل العملاء لسند القبض: $e');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _message(Object message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$message')));
    }
  }

  Future<void> _review() async {
    final saved = await reviewOperation(context, _checkout);
    _record = await _checkout.read();
    if (mounted) {
      if (saved == true) {
        _new();
      } else {
        setState(() {});
      }
    }
  }

  void _new() {
    if (CheckoutService.needsReview(_record)) return;
    setState(() {
      _voucher = null;
      _editing = false;
      _customerId = null;
      _amount.clear();
      _notes.clear();
      _date = DateTime.now();
      _method = 'cash';
    });
  }

  Future<bool> _discard() async {
    if (_readOnly ||
        (_amount.text.isEmpty && _notes.text.isEmpty && _customerId == null)) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ترك السند الحالي؟'),
            content: const Text('سيتم إلغاء التغييرات غير المحفوظة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _load([Map<String, Object> query = const {}]) async {
    if (_busy ||
        CheckoutService.needsReview(_record) ||
        !await _discard() ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _service.document(
        branch,
        receipt: true,
        query: query,
      );
      final rawVoucher = result['voucher'] ?? result['order'];
      if (rawVoucher is! Map) {
        throw const FormatException('لم يُرجع الخادم بيانات سند قبض صالحة.');
      }
      if (!mounted) return;
      setState(() {
        _voucher = Map<String, dynamic>.from(rawVoucher);
        _editing = false;
        _customerId = SaleData.id(_voucher!['party_id']);
        _amount.text = '${_voucher!['amount']}';
        _notes.text = '${_voucher!['notes'] ?? ''}';
        _method = _voucher!['payment_method'] ?? 'cash';
        _date =
            DateTime.tryParse('${_voucher!['payment_date']}') ?? DateTime.now();
      });
    } catch (e) {
      _message('تعذر استرجاع السند: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بحث عن سند قبض'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'رقم السند'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    c.dispose();
    if (mounted && value != null && value.trim().isNotEmpty) {
      await _load({'search': value.trim()});
    }
  }

  Future<void> _print({bool share = false, String? message}) async {
    if (_voucher == null) return;
    final v = _voucher!;
    final order = <String, dynamic>{
      ...v,
      'type': 'receipt',
      'document_title': 'سند قبض',
      'invoice_number': v['voucher_number'],
      'customer_name': v['party']?['name'],
      'total': v['amount'],
      'subtotal': v['amount'],
      'paid_amount': v['amount'],
      'created_at': v['payment_date'],
      'store_name':
          widget.user['tenant']?['name'] ??
          widget.user['tenant_name'] ??
          'Wasla POS',
    };
    try {
      if (share) {
        await PrinterService.shareReceipt(
          order: order,
          items: const [],
          cashierName: '${widget.user['name'] ?? ''}',
          message: message,
        );
      } else {
        await PrinterService.printReceipt(
          order: order,
          items: const [],
          cashierName: '${widget.user['name'] ?? ''}',
        );
      }
    } catch (e) {
      _message('السند محفوظ؛ تعذرت الطباعة أو المشاركة: $e');
    }
  }

  Future<void> _whatsapp() async {
    if (_voucher == null) return;
    await _print(
      share: true,
      message:
          'سند قبض ${_voucher!['voucher_number']}\nالمبلغ: ${money(_voucher!['amount'])}\nشكراً لتعاملكم معنا',
    );
  }

  Future<void> _save({bool print = false}) async {
    if (_locked) return;
    final amount = SaleData.number(_amount.text);
    if (_customerId == null ||
        amount == null ||
        amount <= 0 ||
        amount > 999999999) {
      _message('اختر العميل وأدخل مبلغاً صحيحاً');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _checkout.checkout(
        payload: {
          'branch_id': branch,
          'customer_id': _customerId,
          if (_editing) 'receipt_id': _voucher!['id'],
          'amount': amount,
          'payment_method': _method,
          'payment_date':
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
          'notes': _notes.text.trim(),
        },
        receiptItems: const [],
        cashierName: '${widget.user['name'] ?? ''}',
      );
      try {
        _record = await _checkout.read();
      } catch (_) {}
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _voucher = PaymentSummary.saved(
            Map<String, dynamic>.from(result['order']),
            receipt: true,
          );
          final party = _voucher!['party'];
          if (party is Map) {
            final index = _customers.indexWhere(
              (row) => SaleData.id(row['id']) == SaleData.id(party['id']),
            );
            if (index >= 0) {
              _customers[index] = Map<String, dynamic>.from(party);
            }
          }
          _editing = false;
        });
        _message('تم حفظ سند القبض');
        if (!PaymentSummary.matches(_voucher!['amount'], amount)) {
          setState(() => _busy = false);
          await showPaymentMismatch(context, amount, _voucher!['amount']);
          return;
        }
        if (print) await _print();
        // The screen is ready for the next receipt; the saved one stays in the archive.
        final number = _voucher?['voucher_number'];
        if (mounted) {
          setState(() => _busy = false);
          _new();
          _message('تم حفظ سند القبض ${number ?? ''}؛ جاهز لسند جديد.');
        }
      } else {
        _message(result['message'] ?? 'تعذر حفظ السند');
      }
    } catch (e) {
      try {
        _record = await _checkout.read();
      } catch (_) {}
      _message(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('سند قبض مستقل')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (CheckoutService.needsReview(_record))
                      MaterialBanner(
                        content: const Text(
                          'سند غير محسوم؛ تحقق قبل تسجيل قبض آخر',
                        ),
                        actions: [
                          TextButton(
                            onPressed: _review,
                            child: const Text('التحقق'),
                          ),
                        ],
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (!CheckoutService.needsReview(_record) &&
                                      await _discard() &&
                                      mounted) {
                                    _new();
                                  }
                                },
                          child: const Text('سند جديد'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _load(),
                          child: const Text('آخر سند'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : _search,
                          child: const Text('بحث'),
                        ),
                        if (_voucher != null) ...[
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _load({'before': _voucher!['id']}),
                            child: const Text('السابق'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _load({'after': _voucher!['id']}),
                            child: const Text('التالي'),
                          ),
                          if (_readOnly)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _editing = true),
                              child: const Text('تعديل'),
                            ),
                          if (_editing)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _load({'id': _voucher!['id']}),
                              child: const Text('إلغاء التعديل'),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'سجّل قبضًا على حساب قديم للعميل دون ربطه بأي فاتورة.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    IgnorePointer(
                      ignoring: _locked,
                      child: CustomerPicker(
                        customers: _customers,
                        value: _customerId,
                        label: 'الزبون / المورد',
                        onChanged: (id) => setState(() => _customerId = id),
                      ),
                    ),
                    if (_customer != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'رصيد العميل: ${money(_customer!['current_balance'])}',
                        ),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاريخ السند'),
                      subtitle: Text(
                        '${_date.year}/${_date.month}/${_date.day}',
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: _locked
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (date != null && mounted) {
                                setState(() => _date = date);
                              }
                            },
                    ),
                    TextField(
                      controller: _amount,
                      enabled: !_locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المقبوض',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_method),
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                        DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                        DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('تحويل بنكي'),
                        ),
                        DropdownMenuItem(value: 'cheque', child: Text('شيك')),
                      ],
                      onChanged: _locked
                          ? null
                          : (v) => setState(() => _method = v!),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _notes,
                      enabled: !_locked,
                      maxLines: 3,
                      maxLength: 5000,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                    if (_voucher?['previous_balance'] != null)
                      Text(
                        'الرصيد السابق: ${money(_voucher!['previous_balance'])}',
                      ),
                    if (_voucher?['current_balance'] != null)
                      Text(
                        'الرصيد بعد القبض: ${money(_voucher!['current_balance'])}',
                      ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _locked ? null : () => _save(print: true),
                          child: const Text('حفظ وطباعة'),
                        ),
                        OutlinedButton(
                          onPressed: _locked ? null : () => _save(),
                          child: const Text('حفظ'),
                        ),
                        if (_voucher != null && !_editing) ...[
                          OutlinedButton(
                            onPressed: _busy ? null : () => _print(),
                            child: const Text('طباعة'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _print(share: true),
                            child: const Text('مشاركة PDF'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : _whatsapp,
                            child: const Text('إرسال PDF عبر واتساب'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    ),
  );
}
