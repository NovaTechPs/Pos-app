import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sale_data.dart';
import '../services/sales_history_service.dart';
import '../services/printer_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, required this.user});
  final Map<String, dynamic> user;
  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _service = SalesHistoryService();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _wholesale = false;
  bool _loading = true;
  String? _error;
  DateTimeRange? _period;
  List<dynamic> _orders = [];
  int _page = 1;
  int _lastPage = 1;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetch(
        branchId: SaleData.id(widget.user['branch_id']) ?? 0,
        wholesale: _wholesale,
        page: _page,
        search: _search.text,
        from: _period?.start.toIso8601String().substring(0, 10),
        to: _period?.end.toIso8601String().substring(0, 10),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _orders = data['data'];
        _lastPage = SaleData.id(data['last_page']) ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectPeriod() async {
    final now = DateTime.now();
    final period = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _period,
    );
    if (period == null || !mounted) return;
    setState(() {
      _period = period;
      _page = 1;
    });
    _load();
  }

  Future<void> _details(Map<String, dynamic> order) async {
    final lines = order['items'] as List? ?? [];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(order['invoice_number']?.toString() ?? 'فاتورة'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'العميل: ${order['party']?['name'] ?? order['customer_name'] ?? 'عميل نقدي'}',
                ),
                Text('التاريخ: ${order['created_at'] ?? '—'}'),
                const Divider(),
                ...lines.map(
                  (line) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line['product']?['name'] ?? 'منتج'),
                    subtitle: Text(
                      '${line['quantity']} × ${line['unit_price']}',
                    ),
                    trailing: Text('${line['total_price']}'),
                  ),
                ),
                const Divider(),
                Text('قيمة الأصناف: ${order['subtotal']}'),
                Text('الخصم: ${order['discount'] ?? 0}'),
                Text('الضريبة: ${order['tax_amount'] ?? 0}'),
                Text(
                  'الإجمالي: ${order['total']} ر.س',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'المدفوع: ${order['paid_amount'] ?? 0} • الحالة: ${order['payment_status'] ?? '—'}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('إعادة الطباعة'),
            onPressed: () async {
              try {
                await PrinterService.printReceipt(
                  order: order,
                  items: lines
                      .map(
                        (line) => <String, dynamic>{
                          'name': line['product']?['name'] ?? 'منتج',
                          'quantity': SaleData.number(line['quantity']) ?? 0,
                          'price': SaleData.number(line['unit_price']) ?? 0,
                          'promotion_total': SaleData.number(
                            line['total_price'],
                          ),
                          'is_gift': line['is_gift'] == true,
                        },
                      )
                      .toList(),
                  cashierName: order['cashier_name']?.toString() ?? '—',
                );
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذرت الطباعة: $error')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('سجل الفواتير'),
      actions: [
        IconButton(
          onPressed: _selectPeriod,
          icon: const Icon(Icons.date_range),
          tooltip: 'تصفية حسب الفترة',
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('التجزئة')),
                  ButtonSegment(value: true, label: Text('الجملة')),
                ],
                selected: {_wholesale},
                onSelectionChanged: (value) {
                  _debounce?.cancel();
                  setState(() {
                    _wholesale = value.first;
                    _page = 1;
                  });
                  _load();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'رقم الفاتورة أو اسم العميل',
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    _page = 1;
                    _load();
                  });
                },
              ),
              if (_period != null)
                InputChip(
                  label: Text(
                    '${_period!.start.toIso8601String().substring(0, 10)} — ${_period!.end.toIso8601String().substring(0, 10)}',
                  ),
                  onDeleted: () {
                    setState(() {
                      _period = null;
                      _page = 1;
                    });
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
              ? const Center(child: Text('لا توجد فواتير مطابقة'))
              : ListView.separated(
                  itemCount: _orders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = Map<String, dynamic>.from(_orders[index]);
                    return ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text('${order['invoice_number']}'),
                      subtitle: Text(
                        '${order['party']?['name'] ?? order['customer_name'] ?? 'عميل نقدي'} • ${order['created_at']}',
                      ),
                      trailing: Text('${order['total']} ر.س'),
                      onTap: () => _details(order),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _loading || _page <= 1
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
              Text('صفحة $_page من $_lastPage'),
              IconButton(
                onPressed: _loading || _page >= _lastPage
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
