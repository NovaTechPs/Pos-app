import '../widgets/product_add_dialog.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/customer_service.dart';
import '../services/pos_service.dart';
import '../services/wholesale_service.dart';
import '../services/checkout_service.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/barcode_service.dart';
import '../services/printer_service.dart';
import '../services/offline_store.dart';
import '../services/operation_id.dart';
import '../models/sale_data.dart';
import '../models/payment_summary.dart';
import '../widgets/payment_confirmation.dart';
import '../models/product_catalog.dart';
import '../widgets/customer_picker.dart';
import '../widgets/wholesale_cart_line.dart';
import '../widgets/operation_review.dart';
import 'wholesale_receipt_screen.dart';

class WholesaleScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const WholesaleScreen({
    super.key,
    required this.user,
    this.salesInvoice = false,
  });
  final bool salesInvoice;
  @override
  State<WholesaleScreen> createState() => _WholesaleScreenState();
}

class _WholesaleScreenState extends State<WholesaleScreen>
    with WidgetsBindingObserver {
  final _service = WholesaleService();
  final _customerService = CustomerService();
  final _searchController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _paidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _searchFocus = FocusNode();
  List<dynamic> _products = [], _customers = [];
  final List<Map<String, dynamic>> _cart = [];
  final Set<int> _invalidLines = {};
  int? _customerId, _previousId, _nextId;
  Map<String, dynamic>? _invoice, _lastSaved, _record;
  bool _loading = true, _saving = false, _editing = false, _whatsapp = false;
  String? _error;
  String _search = '', _paymentMethod = 'cash', _discountType = 'fixed';
  int _page = 0;
  ProductCatalog _catalogIndex = ProductCatalog([]);
  Timer? _scanTimer, _draftTimer;
  Future<void> _draftWrite = Future.value();
  String _draftToken = OperationId.create();
  late final CheckoutService _checkout;
  late final OfflineStore _drafts;
  int get _branchId => SaleData.id(widget.user['branch_id']) ?? 0;
  bool get _readOnly => _invoice != null && !_editing;
  bool get _locked =>
      _readOnly || _saving || CheckoutService.needsReview(_record);
  double number(Object? value) => SaleData.number(value) ?? 0;
  double get _subtotal => _cart.fold(
    0,
    (sum, row) =>
        sum +
        (number(row['price']) * number(row['quantity']) * 100).round() / 100,
  );
  double get _discount => _discountType == 'percentage'
      ? (_subtotal * number(_discountController.text) / 100 * 100).round() / 100
      : number(_discountController.text);
  double get _total => (_subtotal - _discount).clamp(0, double.infinity);
  double get _paid =>
      _paidController.text.trim().isEmpty ? 0 : number(_paidController.text);
  Map<String, dynamic>? get _linkedReceipt {
    final raw = _invoice?['linked_receipt'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  double get _linkedReceiptAmount =>
      number(_linkedReceipt?['amount'] ?? _invoice?['collected_amount']);
  Map<String, dynamic>? get _customer {
    for (final raw in _customers) {
      if (SaleData.id(raw['id']) == _customerId) {
        return Map<String, dynamic>.from(raw);
      }
    }
    final party = _invoice?['party'];
    return party is Map && SaleData.id(party['id']) == _customerId
        ? Map<String, dynamic>.from(party)
        : null;
  }

  String money(Object? value) => number(value).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final scope = [
      ApiConfig.baseUrl,
      widget.user['tenant_id'],
      widget.user['id'],
      _branchId,
      widget.salesInvoice ? 'sales-invoice' : 'wholesale',
    ].join('|');
    _drafts = OfflineStore('$scope-draft');
    _checkout = CheckoutService(
      scope: scope,
      send: (payload) => ApiClient.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/${widget.salesInvoice ? 'pos' : 'wholesale'}/orders',
        ),
        body: payload,
      ),
    );
    _loadData(restore: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _persist();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _draftTimer?.cancel();
    _persist();
    for (final c in [
      _searchController,
      _discountController,
      _paidController,
      _notesController,
    ]) {
      c.dispose();
    }
    _searchFocus.dispose();
    super.dispose();
  }

  void _message(Object value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$value')));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _persist() {
    if (_readOnly || _loading) return;
    final data = <String, dynamic>{
      'draft_uuid': _draftToken,
      'items': _cart.map((r) => Map<String, dynamic>.from(r)).toList(),
      'customer_id': _customerId,
      'discount_type': _discountType,
      'discount': _discountController.text,
      'paid': _paidController.text,
      'payment_method': _paymentMethod,
      'notes': _notesController.text,
      'invoice': _editing ? _invoice : null,
    };
    _draftWrite = _draftWrite
        .then((_) => _drafts.saveDraft(_branchId, data))
        .catchError((Object e) {
          _message('تعذر حفظ مسودة الجملة: $e');
        });
  }

  Future<void> _loadData({
    bool restore = false,
    bool background = false,
  }) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (_branchId <= 0) throw Exception('اختر الفرع أولاً.');
      final results = await Future.wait<Object?>([
        _service.fetchProducts(_branchId),
        _customerService.fetchWholesaleParties(),
        _checkout.read(),
        if (restore) _drafts.draft(_branchId),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List;
        _catalogIndex = ProductCatalog([
          {'id': 0, 'products': _products},
        ]);
        _customers = results[1] as List;
        _record = results[2] as Map<String, dynamic>?;
        if (restore &&
            _cart.isEmpty &&
            results.length > 3 &&
            results[3] is Map) {
          final draft = results[3] as Map;
          if (_record?['status'] == 'confirmed' &&
              draft['draft_uuid'] != null &&
              draft['draft_uuid'] == _record?['payload']?['draft_uuid']) {
            _loading = false;
            return;
          }
          _draftToken = draft['draft_uuid']?.toString() ?? OperationId.create();
          _cart.addAll(
            (draft['items'] as List? ?? []).map(
              (r) => Map<String, dynamic>.from(r),
            ),
          );
          _customerId = SaleData.id(draft['customer_id']);
          _discountType = draft['discount_type'] ?? 'fixed';
          _discountController.text = '${draft['discount'] ?? 0}';
          _paidController.text = '${draft['paid'] ?? ''}';
          _paymentMethod = draft['payment_method'] ?? 'cash';
          _notesController.text = '${draft['notes'] ?? ''}';
          if (draft['invoice'] is Map) {
            _invoice = Map<String, dynamic>.from(draft['invoice']);
            _editing = true;
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (background) {
        _message('تم الحفظ، لكن تعذر تحديث بيانات الأصناف: $e');
      } else if (mounted) {
        setState(() {
          _error = 'تعذر التحميل: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _reviewSale() async {
    try {
      final saved = await reviewOperation(context, _checkout);
      if (!mounted || saved == null) return;
      _record = await _checkout.read();
      if (!mounted) return;
      if (saved) {
        _reset();
      } else {
        setState(() {});
      }
    } catch (e) {
      _message(e);
    }
  }

  void _scanInput(String value) {
    _scanTimer?.cancel();
    setState(() {
      _search = value;
      _page = 0;
    });
    _scanTimer = Timer(const Duration(milliseconds: 180), () {
      if (_catalogIndex.isCompleteBarcode(value)) _scanExact(value);
    });
  }

  void _scanExact(String value) {
    _scanTimer?.cancel();
    final code = BarcodeService.normalize(value);
    if (code.isEmpty) return;
    final product = _catalogIndex.findBarcode(code);
    if (product != null) _addProduct(product);
  }

  double _available(Map<String, dynamic> item) {
    var available = number(item['stock_quantity']);
    if (_editing) {
      for (final raw in _invoice?['items'] as List? ?? []) {
        if (SaleData.id(raw['product_id']) == SaleData.id(item['id'])) {
          available += number(raw['quantity']);
        }
      }
    }
    return available;
  }

  Future<void> _addMobileProduct(Map<String, dynamic> product) async {
    if (_locked) return;
    final customerId = _customerId;
    final existing = _cart.where((r) => r['id'] == product['id']).firstOrNull;
    final selection = await showDialog<ProductSelection>(
      context: context,
      builder: (_) => ProductAddDialog(
        product: product,
        price: number(product['price']),
        minimum: number(product['min_wholesale_quantity'])
            .clamp(1, double.infinity),
        available: _service.allowNegativeStock
            ? null
            : _available(product) - number(existing?['quantity']),
        loadHistory: customerId == null
            ? null
            : () => _service.priceHistory(
                _branchId,
                customerId,
                SaleData.id(product['id'])!,
              ),
      ),
    );
    if (!mounted || selection == null || _locked || customerId != _customerId) {
      return;
    }
    final quantity = number(existing?['quantity']) + selection.quantity;
    if (!_service.allowNegativeStock && quantity > _available(product)) {
      _message('الكمية تتجاوز المخزون المتاح');
      return;
    }
    if (existing == null) {
      _cart.add({...product, 'price': selection.price, 'quantity': quantity});
    } else {
      existing['price'] = selection.price;
      existing['quantity'] = quantity;
    }
    _changed();
  }

  void _addProduct(Map<String, dynamic> product) {
    if (_locked) return;
    final existing = _cart.indexWhere((r) => r['id'] == product['id']);
    final minimum = number(product['min_wholesale_quantity'])
        .clamp(1, double.infinity);
    final quantity = existing < 0
        ? minimum
        : number(_cart[existing]['quantity']) + 1;
    if (!_service.allowNegativeStock && quantity > _available(product)) {
      _message('الكمية تتجاوز المخزون المتاح');
      return;
    }
    if (existing < 0) {
      _cart.add({...product, 'quantity': quantity});
    } else {
      _cart[existing]['quantity'] = quantity;
    }
    _searchController.clear();
    _search = '';
    _page = 0;
    _changed();
    _searchFocus.requestFocus();
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
  void _reset() {
    setState(() {
      _draftToken = OperationId.create();
      _cart.clear();
      _invalidLines.clear();
      _invoice = null;
      _editing = false;
      _customerId = null;
      _previousId = null;
      _nextId = null;
      _discountController.text = '0';
      _discountType = 'fixed';
      _paidController.text = '0';
      _notesController.clear();
    });
    _persist();
    _searchFocus.requestFocus();
  }

  Future<void> _newInvoice() async {
    if (_saving || CheckoutService.needsReview(_record)) return;
    if (!_readOnly &&
        _cart.isNotEmpty &&
        !await _confirm(
          'فاتورة جديدة',
          'سيتم إفراغ الفاتورة الحالية. هل تريد المتابعة؟',
        )) {
      return;
    }
    if (mounted) _reset();
  }

  Future<void> _browse([Map<String, Object> query = const {}]) async {
    if (_saving || CheckoutService.needsReview(_record)) return;
    if (!_readOnly &&
        _cart.isNotEmpty &&
        !await _confirm(
          'استعراض الفواتير',
          'سيتم استبدال المسودة الحالية بالفاتورة المختارة.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final data = widget.salesInvoice
          ? <String, dynamic>{
              'order': await PosService().fetchInvoice(
                _branchId,
                before: SaleData.id(query['before']),
                after: SaleData.id(query['after']),
                search:
                    query['search']?.toString() ??
                    (query.containsKey('id')
                        ? (_invoice?['invoice_number'])?.toString()
                        : null),
              ),
            }
          : await _service.document(_branchId, query: query);
      if (!mounted) return;
      final order = Map<String, dynamic>.from(data['order']);
      setState(() {
        _invoice = order;
        _editing = false;
        _previousId = SaleData.id(data['previous_id']);
        _nextId = SaleData.id(data['next_id']);
        _customerId = SaleData.id(order['customer_id']);
        _discountType = order['discount_type'] ?? 'fixed';
        _discountController.text =
            '${_discountType == 'percentage' ? order['discount_rate'] ?? 0 : order['discount'] ?? 0}';
        _paidController.text =
            '${order['collected_amount'] ?? order['paid_amount'] ?? 0}';
        _paymentMethod = order['payment_method'] ?? 'cash';
        _notesController.text = '${order['notes'] ?? ''}';
        _cart.clear();
        _invalidLines.clear();
        for (final raw in order['items'] as List? ?? []) {
          final productId = SaleData.id(raw['product_id']);
          final product = _products
              .cast<Map>()
              .where((p) => SaleData.id(p['id']) == productId)
              .firstOrNull;
          _cart.add({
            ...?product?.cast<String, dynamic>(),
            'id': productId,
            'name': raw['product']?['name'] ?? product?['name'] ?? 'صنف',
            'quantity': number(raw['quantity']),
            'price': number(raw['unit_price']),
            'min_wholesale_quantity': product?['min_wholesale_quantity'] ?? 1,
            'stock_quantity': product?['stock_quantity'] ?? 0,
          });
        }
      });
      // Viewing a historical invoice must not resurrect the discarded draft.
      _draftTimer?.cancel();
      await _draftWrite;
      await _drafts.saveDraft(_branchId, {'items': []});
    } catch (e) {
      _message('تعذر استرجاع الفاتورة: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _searchInvoice() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بحث عن فاتورة'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'رقم الفاتورة'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
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
      await _browse({'search': value.trim()});
    }
  }

  Future<void> _priceHistory(Map<String, dynamic> item) async {
    if (_customerId == null) {
      _message('اختر العميل لعرض آخر أسعار البيع له');
      return;
    }
    try {
      final rows = await _service.priceHistory(
        _branchId,
        _customerId!,
        SaleData.id(item['id'])!,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Text(
                  'آخر أسعار ${item['name']}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('لا توجد مبيعات سابقة لهذا العميل'),
                  ),
                Expanded(
                  child: ListView(
                    children: rows
                        .map<Widget>(
                          (r) => ListTile(
                            title: Text(
                              'السعر ${money(r['unit_price'])} • الكمية ${r['quantity']}',
                            ),
                            subtitle: Text('${r['created_at']}'),
                            trailing: _locked ? null : const Icon(Icons.check),
                            onTap: _locked
                                ? null
                                : () {
                                    item['price'] = number(r['unit_price']);
                                    _changed();
                                    Navigator.pop(ctx);
                                  },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _message(e);
    }
  }

  List<Map<String, dynamic>> _receiptItems(Map<String, dynamic> order) =>
      (order['items'] as List? ?? [])
          .map(
            (r) => <String, dynamic>{
              'name': r['product']?['name'] ?? r['name'] ?? 'صنف',
              'price': number(r['unit_price'] ?? r['price']),
              'quantity': number(r['quantity']),
              'unit': r['unit'] ?? r['product']?['unit'],
              'product_number':
                  r['product_number'] ??
                  r['product']?['product_number'] ??
                  r['product_id'],
            },
          )
          .toList();
  Future<void> _print(
    Map<String, dynamic> order, {
    bool share = false,
    String? message,
  }) async {
    try {
      final data = {
        ...order,
        'customer_name': order['party']?['name'] ?? order['customer_name'],
        'store_phone': order['store_phone'] ?? widget.user['tenant']?['phone'],
        'store_address':
            order['store_address'] ?? widget.user['tenant']?['address'],
        'store_name':
            widget.user['tenant']?['name'] ??
            widget.user['tenant_name'] ??
            'Wasla POS',
      };
      if (share) {
        await PrinterService.shareReceipt(
          order: data,
          items: _receiptItems(order),
          cashierName: '${widget.user['name'] ?? ''}',
          message: message,
        );
      } else {
        await PrinterService.printReceipt(
          order: data,
          items: _receiptItems(order),
          cashierName: '${widget.user['name'] ?? ''}',
        );
      }
    } catch (e) {
      _message('الفاتورة محفوظة؛ تعذرت الطباعة أو مشاركة PDF: $e');
    }
  }

  Future<void> _openWhatsApp(Map<String, dynamic> order) async {
    final collected = order['collected_amount'] ?? order['paid_amount'];
    final currentBalance =
        SaleData.number(order['current_balance']) ??
        SaleData.number(order['party']?['current_balance']);
    final balanceLine = currentBalance == null
        ? ''
        : currentBalance < -.005
        ? '\nرصيد لصالح العميل بعد الدفعة: ${money(-currentBalance)}'
        : '\nالرصيد المتبقي على العميل بعد الدفعة: ${money(currentBalance)}';
    final text =
        '${widget.salesInvoice ? 'فاتورة مبيعات' : 'فاتورة جملة'} ${order['invoice_number']}\nالإجمالي: ${money(order['total'])}\nالمبلغ المستلم من العميل: ${money(collected)}$balanceLine\nشكراً لتعاملكم معنا';
    try {
      await _print(order, share: true, message: text);
    } catch (e) {
      _message('تعذرت مشاركة ملف PDF: $e');
    }
  }

  Future<void> _save({bool print = false}) async {
    if (_locked || _cart.isEmpty) return;
    if (_invalidLines.isNotEmpty) {
      _message('صحّح السعر أو الكمية في السلة قبل الحفظ');
      return;
    }
    if (!widget.salesInvoice && !_service.workspaceAvailable) {
      _message(
        'يلزم نشر تحديث الـAPI على الخادم لاستخدام شاشة الجملة الجديدة.',
      );
      return;
    }
    final rawDiscount = SaleData.number(_discountController.text);
    final rawPaid = _paidController.text.trim().isEmpty
        ? 0
        : SaleData.number(_paidController.text);
    if (rawDiscount == null ||
        rawDiscount < 0 ||
        (_discountType == 'percentage'
            ? rawDiscount > 100
            : rawDiscount > _subtotal) ||
        rawPaid == null ||
        rawPaid < 0 ||
        (_customerId == null && (rawPaid - _total).abs() > .005)) {
      _message('اختر عميلاً عند وجود مبلغ متبقٍ أو دفعة زائدة عن الفاتورة');
      return;
    }
    bool belowCost = _cart.any(
      (r) => number(r['price']) < number(r['cost_price']),
    );
    if (belowCost &&
        !_service.canSellBelowCost &&
        !await _confirm(
          'البيع بأقل من التكلفة',
          'يوجد صنف سعره أقل من التكلفة. هل تريد المتابعة؟',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      _draftTimer?.cancel();
      _persist();
      await _draftWrite;
      final result = await _checkout.checkout(
        payload: {
          'draft_uuid': _draftToken,
          'branch_id': _branchId,
          'customer_id': _customerId,
          if (_editing) 'invoice_id': _invoice!['id'],
          'items': _cart
              .map(
                (r) => {
                  'product_id': r['id'],
                  'quantity': r['quantity'],
                  'price': r['price'],
                },
              )
              .toList(),
          if (widget.salesInvoice) ...{
            'subtotal': _subtotal,
            'discount': _discount,
            'tax_amount': 0,
            'delivery_fee': 0,
            'total_amount': _total,
          },
          'discount_type': _discountType,
          'discount_amount': _discount,
          'discount_rate': _discountType == 'percentage' ? rawDiscount : 0,
          'paid_amount': rawPaid,
          'payment_method': _paymentMethod,
          'notes': _notesController.text.trim(),
          'confirm_below_cost': belowCost,
        },
        receiptItems: _cart.map((r) => Map<String, dynamic>.from(r)).toList(),
        cashierName: '${widget.user['name'] ?? ''}',
      );
      try {
        _record = await _checkout.read();
      } catch (_) {}
      if (!mounted) return;
      if (result['success'] == true) {
        final order = PaymentSummary.saved(
          Map<String, dynamic>.from(result['order']),
        );
        final whatsapp = _whatsapp;
        _lastSaved = order;
        _reset();
        _message(
          'تم حفظ ${widget.salesInvoice ? 'فاتورة المبيعات' : 'فاتورة الجملة'} ${order['invoice_number']}',
        );
        unawaited(_loadData(background: true));
        final collected = order['collected_amount'] ?? order['paid_amount'];
        if (!PaymentSummary.matches(collected, rawPaid)) {
          setState(() => _saving = false);
          await showPaymentMismatch(context, rawPaid, collected);
          return;
        }
        if (print) await _print(order);
        if (whatsapp) await _openWhatsApp(order);
      } else {
        _message(result['message'] ?? 'تعذر الحفظ');
      }
    } catch (e) {
      try {
        _record = await _checkout.read();
      } catch (_) {}
      _message('تعذر الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _amountRow(String label, Object? amount, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              money(amount),
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: bold ? 20 : 15,
              ),
            ),
          ],
        ),
      );
  /// Rebuilds the open catalog picker; its dialog is built from this state.
  StateSetter? _pickerRefresh;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _pickerRefresh?.call(() {});
  }

  void _pickProduct(bool inDialog, VoidCallback add) {
    // Only the picker dialog closes; the inline list must keep the screen.
    if (inDialog) Navigator.of(context).pop();
    add();
  }

  Widget _catalog({bool inDialog = false}) {
    final products = _catalogIndex.search(_search, null);
    final pageSize = MediaQuery.sizeOf(context).width < 600 ? 6 : 12;
    final pages = (products.length / pageSize).ceil().clamp(1, 1000000);
    final page = _page.clamp(0, pages - 1);
    final visible = products.skip(page * pageSize).take(pageSize).toList();
    return Card(
      key: const ValueKey('wholesale-products-section'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الأصناف', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              // One FocusNode can belong to one field; the inline field keeps it.
              focusNode: inDialog ? null : _searchFocus,
              autofocus: inDialog,
              onChanged: _scanInput,
              onSubmitted: _scanExact,
              onEditingComplete: () {},
              decoration: const InputDecoration(
                hintText: 'ابحث عن صنف أو امسح الباركود',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد أصناف مطابقة'),
              ),
            if (MediaQuery.sizeOf(context).width < 1050)
              ...visible.map((raw) {
                final product = Map<String, dynamic>.from(raw);
                return MobileProductRow(
                  product: product,
                  price: number(product['price']),
                  onTap: _locked
                      ? null
                      : () => _pickProduct(
                          inDialog,
                          () => _addMobileProduct(product),
                        ),
                );
              })
            else
              LayoutBuilder(
                builder: (ctx, box) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: box.maxWidth > 600 ? 3 : 2,
                    mainAxisExtent: 160,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final p = Map<String, dynamic>.from(visible[i]);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _locked
                            ? null
                            : () => _pickProduct(inDialog, () => _addProduct(p)),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.amber,
                                size: 28,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${p['name']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                money(p['price']),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                              Text(
                                'متوفر ${money(p['stock_quantity'])}',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                              if (number(p['min_wholesale_quantity']) > 1)
                                Text(
                                  'أقل كمية ${p['min_wholesale_quantity']}',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                Text('${page + 1} / $pages'),
                IconButton(
                  onPressed: page + 1 < pages
                      ? () => setState(() => _page = page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCatalogPicker() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, refresh) {
          _pickerRefresh = refresh;
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                height: MediaQuery.sizeOf(dialogContext).height * .78,
                child: SingleChildScrollView(child: _catalog(inDialog: true)),
              ),
            ),
          );
        },
      ),
    );
    _pickerRefresh = null;
  }

  Widget _section(String title, String key, List<Widget> children) => Card(
    key: ValueKey(key),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Future<void> _addCustomerPayment() async {
    if (_saving || CheckoutService.needsReview(_record)) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WholesaleReceiptScreen(
          user: widget.user,
          customers: _customers,
          initialCustomerId: _customerId,
        ),
      ),
    );
    if (!mounted) return;
    try {
      final customers = await _customerService.fetchWholesaleParties();
      if (mounted) setState(() => _customers = customers);
    } catch (error) {
      _message('تعذر تحديث رصيد الزبون: $error');
    }
  }

  String _paymentMethodLabel(String method) => switch (method) {
    'card' => 'بطاقة',
    'bank_transfer' => 'تحويل بنكي',
    'cheque' => 'شيك',
    _ => 'نقدي',
  };

  Future<void> _editLinkedReceipt() async {
    final invoice = _invoice;
    if (invoice == null || _saving || CheckoutService.needsReview(_record)) {
      return;
    }
    final receipt = _linkedReceipt;
    final amount = TextEditingController(text: money(_linkedReceiptAmount));
    final notes = TextEditingController(text: '${receipt?['notes'] ?? ''}');
    var customerId =
        SaleData.id(receipt?['party_id']) ??
        SaleData.id(invoice['customer_id']);
    var method =
        '${receipt?['payment_method'] ?? invoice['payment_method'] ?? 'cash'}';
    var date =
        DateTime.tryParse(
          '${receipt?['payment_date'] ?? invoice['created_at'] ?? ''}',
        ) ??
        DateTime.now();
    var saved = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('تعديل سند الفاتورة'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تعديل السند مستقل عن بيانات وأصناف الفاتورة.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 14),
                    CustomerPicker(
                      customers: _customers,
                      value: customerId,
                      label: 'الزبون / المورد',
                      onChanged: busy
                          ? (_) {}
                          : (value) => setDialogState(() {
                              customerId = value;
                              error = null;
                            }),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاريخ السند'),
                      subtitle: Text('${date.year}/${date.month}/${date.day}'),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: busy
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: dialogContext,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selected != null) {
                                setDialogState(() => date = selected);
                              }
                            },
                    ),
                    TextField(
                      controller: amount,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'قيمة السند',
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(method),
                      initialValue: method,
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
                      onChanged: busy
                          ? null
                          : (value) => setDialogState(() {
                              method = value ?? 'cash';
                              error = null;
                            }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      enabled: !busy,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 5000,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final value = SaleData.number(amount.text);
                        if (customerId == null ||
                            value == null ||
                            value < 0 ||
                            value > 999999999) {
                          setDialogState(
                            () => error = 'اختر العميل وأدخل قيمة سند صحيحة.',
                          );
                          return;
                        }
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          final result = await _service.updateInvoiceReceipt(
                            salesInvoice: widget.salesInvoice,
                            orderId: SaleData.id(invoice['id'])!,
                            payload: {
                              'branch_id': _branchId,
                              'customer_id': customerId,
                              'amount': value,
                              'payment_method': method,
                              'payment_date':
                                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                              'notes': notes.text.trim(),
                            },
                          );
                          if (!mounted) return;
                          final rawOrder = result['order'];
                          if (rawOrder is! Map) {
                            throw const FormatException(
                              'لم يُرجع الخادم بيانات الفاتورة بعد حفظ السند.',
                            );
                          }
                          final rawVoucher = result['voucher'];
                          final updatedOrder = Map<String, dynamic>.from(
                            rawOrder,
                          );
                          final voucher = rawVoucher is Map
                              ? Map<String, dynamic>.from(rawVoucher)
                              : null;
                          final party =
                              voucher?['party'] ?? updatedOrder['party'];
                          setState(() {
                            _invoice = {
                              ...invoice,
                              ...updatedOrder,
                              'linked_receipt': voucher,
                            };
                            _editing = true;
                            _customerId = SaleData.id(
                              updatedOrder['customer_id'],
                            );
                            _paidController.text = money(value);
                            _paymentMethod = method;
                            if (party is Map) {
                              final partyMap = Map<String, dynamic>.from(party);
                              final index = _customers.indexWhere(
                                (row) =>
                                    SaleData.id(row['id']) ==
                                    SaleData.id(partyMap['id']),
                              );
                              if (index >= 0) _customers[index] = partyMap;
                            }
                          });
                          saved = true;
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          _message(
                            'تم حفظ السند. يمكنك الآن متابعة تعديل الفاتورة.',
                          );
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              busy = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: const Text('حفظ السند'),
              ),
            ],
          ),
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    amount.dispose();
    notes.dispose();
    if (saved && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  Widget _linkedReceiptPanel() {
    final receipt = _linkedReceipt;
    final value = _linkedReceiptAmount;
    final currentBalance =
        receipt?['current_balance'] ??
        _invoice?['current_balance'] ??
        receipt?['party']?['current_balance'];
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              receipt == null
                  ? 'سند القبض المرتبط'
                  : 'سند القبض المرتبط بالفاتورة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _amountRow('قيمة السند', value, bold: true),
            if (receipt != null) ...[
              Row(
                children: [
                  const Expanded(child: Text('طريقة الدفع')),
                  Text(
                    _paymentMethodLabel(
                      '${receipt['payment_method'] ?? 'cash'}',
                    ),
                  ),
                ],
              ),
              if (receipt['payment_date'] != null)
                Text('تاريخ السند: ${receipt['payment_date']}'),
            ],
            if (currentBalance != null)
              _amountRow('رصيد العميل بعد السند', currentBalance),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _saving || CheckoutService.needsReview(_record)
                  ? null
                  : _editLinkedReceipt,
              icon: const Icon(Icons.edit_note),
              label: Text(
                receipt == null ? 'إضافة سند للفاتورة' : 'تعديل السند',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'قيمة السند لا تتغير من خانة المدفوع في الفاتورة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerPanel() {
    final customer = _customer;
    final balanceDirection = customer?['type'] == 'supplier' ? -1 : 1;
    var previous = number(customer?['current_balance']);
    if (_editing && _customerId == SaleData.id(_invoice?['customer_id'])) {
      previous -=
          balanceDirection *
          (number(_invoice?['total']) -
              number(
                _invoice?['collected_amount'] ?? _invoice?['paid_amount'],
              ));
    }
    return Card(
      key: const ValueKey('wholesale-customer-section'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: IgnorePointer(
                    ignoring: _locked,
                    child: CustomerPicker(
                      customers: _customers,
                      value: _customerId,
                      label: 'الزبون / المورد',
                      placeholder: 'عميل نقدي / عابر',
                      onChanged: (value) {
                        _customerId = value;
                        _changed();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _locked ? null : _openCatalogPicker,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('إضافة صنف'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'إجراءات الفاتورة',
                  onSelected: (action) {
                    switch (action) {
                      case 'new':
                        _newInvoice();
                      case 'browse':
                        _browse();
                      case 'search':
                        _searchInvoice();
                      case 'previous':
                        _browse(
                          widget.salesInvoice
                              ? {'before': _invoice!['id']}
                              : {'id': _previousId!},
                        );
                      case 'next':
                        _browse(
                          widget.salesInvoice
                              ? {'after': _invoice!['id']}
                              : {'id': _nextId!},
                        );
                      case 'edit':
                        _editing = true;
                        _changed();
                      case 'cancel-edit':
                        _browse({'id': _invoice!['id']});
                      case 'receipt':
                        _addCustomerPayment();
                      case 'invoice-receipt':
                        _editLinkedReceipt();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'new', child: Text('فاتورة جديدة')),
                    const PopupMenuItem(value: 'browse', child: Text('آخر فاتورة')),
                    const PopupMenuItem(value: 'search', child: Text('بحث عن فاتورة')),
                    if (_invoice != null &&
                        (widget.salesInvoice || _previousId != null))
                      const PopupMenuItem(value: 'previous', child: Text('الفاتورة السابقة')),
                    if (_invoice != null &&
                        (widget.salesInvoice || _nextId != null))
                      const PopupMenuItem(value: 'next', child: Text('الفاتورة التالية')),
                    if (_readOnly)
                      const PopupMenuItem(value: 'edit', child: Text('تعديل الفاتورة')),
                    if (_editing)
                      const PopupMenuItem(value: 'cancel-edit', child: Text('إلغاء التعديل')),
                    const PopupMenuItem(value: 'receipt', child: Text('سند قبض مستقل')),
                    if (_invoice != null)
                      const PopupMenuItem(value: 'invoice-receipt', child: Text('تعديل سند الفاتورة')),
                  ],
                ),
              ],
            ),
            if (customer != null || _invoice != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (customer != null)
                      Expanded(
                        child: Text(
                          '${_readOnly ? 'رصيد العميل' : 'الرصيد السابق'}: ${money(previous)}'
                          '${_readOnly ? '' : '  •  بعد الفاتورة: ${money(previous + balanceDirection * (_total - _paid))}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (_invoice != null)
                      Text(
                        'فاتورة ${_invoice!['invoice_number'] ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_invoice != null && _linkedReceipt != null)
                      TextButton(
                        onPressed: _saving ? null : _editLinkedReceipt,
                        child: Text('السند ${money(_linkedReceiptAmount)}'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartPanel() => Card(
    key: const ValueKey('wholesale-cart-section'),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الأصناف في الفاتورة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${_cart.length} أصناف'),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إضافة صنف',
                onPressed: _locked ? null : _openCatalogPicker,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const Divider(height: 1),
          // The page itself scrolls, so the list gets a bounded height
          // instead of Expanded (which fails layout inside a scroll view).
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: _cart.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('اختر الأصناف لبدء الفاتورة')),
                  )
                : ListView.separated(
                    key: const ValueKey('wholesale-items-table-scroll'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _cart[index];
                      return WholesaleCartLine(
                        key: ValueKey('wholesale-cart-line-${row['id']}'),
                        id: SaleData.id(row['id']) ?? 0,
                        name: '${row['name']}',
                        price: number(row['price']),
                        quantity: number(row['quantity']),
                        minimum: number(row['min_wholesale_quantity']) > 0
                            ? number(row['min_wholesale_quantity'])
                            : 1,
                        available: _available(row),
                        allowNegative: _service.allowNegativeStock,
                        enabled: !_locked,
                        onChanged: (price, quantity) {
                          row['price'] = price;
                          row['quantity'] = quantity;
                          _changed();
                        },
                        onValidity: (valid) {
                          final id = SaleData.id(row['id']) ?? 0;
                          if (valid) {
                            _invalidLines.remove(id);
                          } else {
                            _invalidLines.add(id);
                          }
                        },
                        onRemove: () {
                          _invalidLines.remove(SaleData.id(row['id']) ?? 0);
                          _cart.remove(row);
                          _changed();
                        },
                        onHistory: () => _priceHistory(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _summaryPanel() =>
      _section('ملخص الفاتورة', 'wholesale-summary-section', [
        _amountRow('المجموع', _subtotal),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_discountType),
                initialValue: _discountType,
                decoration: const InputDecoration(labelText: 'نوع الخصم'),
                items: const [
                  DropdownMenuItem(value: 'fixed', child: Text('مبلغ')),
                  DropdownMenuItem(value: 'percentage', child: Text('نسبة %')),
                ],
                onChanged: _locked
                    ? null
                    : (v) {
                        _discountType = v!;
                        _changed();
                      },
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _discountController,
                enabled: !_locked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'الخصم'),
                onChanged: (_) => _changed(),
              ),
            ),
          ],
        ),
        _amountRow('الصافي للدفع', _total, bold: true),
      ]);

  Widget _paymentPanel() => _section(
    'الدفع والطباعة',
    'wholesale-payment-section',
    [
      TextField(
        controller: _paidController,
        enabled: !_locked && _invoice == null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'المدفوع',
          hintText: '0.00',
          helperText: _invoice == null
              ? null
              : 'عدّلها من زر «تعديل السند» أعلى الفاتورة.',
        ),
        onChanged: (_) => _changed(),
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final amount in [50, 100, 200])
            TextButton(
              onPressed: _locked || _invoice != null
                  ? null
                  : () {
                      _paidController.text = money(
                        amount > _total ? _total : amount,
                      );
                      _changed();
                    },
              child: Text('$amount'),
            ),
          TextButton(
            onPressed: _locked || _invoice != null
                ? null
                : () {
                    _paidController.text = money(_total);
                    _changed();
                  },
            child: const Text('كامل المبلغ'),
          ),
        ],
      ),
      _amountRow('المتبقي على الحساب', _total - _paid),
      if (_paid > _total + .005 && _customerId != null)
        _amountRow('الزيادة تسدد الرصيد أو تصبح رصيداً للعميل', _paid - _total),
      DropdownButtonFormField<String>(
        key: ValueKey(_paymentMethod),
        initialValue: _paymentMethod,
        decoration: const InputDecoration(labelText: 'طريقة الدفع'),
        items: const [
          DropdownMenuItem(value: 'cash', child: Text('نقدي')),
          DropdownMenuItem(value: 'card', child: Text('بطاقة')),
          DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل بنكي')),
          DropdownMenuItem(value: 'cheque', child: Text('شيك')),
        ],
        onChanged: _locked || _invoice != null
            ? null
            : (v) {
                _paymentMethod = v!;
                _changed();
              },
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _notesController,
        enabled: !_locked,
        maxLines: 2,
        maxLength: 500,
        decoration: const InputDecoration(labelText: 'ملاحظات'),
        onChanged: (_) => _changed(),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('إرسال PDF عبر واتساب بعد الحفظ'),
        value: _whatsapp,
        onChanged: _locked ? null : (v) => setState(() => _whatsapp = v!),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _locked || _cart.isEmpty
                ? null
                : () => _save(print: true),
            icon: const Icon(Icons.print),
            label: const Text('حفظ وطباعة'),
          ),
          OutlinedButton.icon(
            onPressed: _locked || _cart.isEmpty ? null : () => _save(),
            icon: const Icon(Icons.save),
            label: const Text('حفظ الفاتورة'),
          ),
        ],
      ),
      if (_invoice != null)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => _print(_invoice!),
              child: const Text('طباعة'),
            ),
            TextButton(
              onPressed: () => _print(_invoice!, share: true),
              child: const Text('مشاركة PDF'),
            ),
            TextButton(
              onPressed: () => _openWhatsApp(_invoice!),
              child: const Text('إرسال PDF عبر واتساب'),
            ),
          ],
        ),
      if (_lastSaved != null && _invoice == null)
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _print(_lastSaved!),
              child: const Text('طباعة آخر فاتورة'),
            ),
            TextButton(
              onPressed: () => _print(_lastSaved!, share: true),
              child: const Text('مشاركة آخر فاتورة'),
            ),
          ],
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.salesInvoice ? 'فاتورة مبيعات' : 'مبيعات الجملة'),
        actions: [
          IconButton(
            onPressed: _saving ? null : () => _loadData(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  FilledButton(
                    onPressed: () => _loadData(restore: true),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    if (CheckoutService.needsReview(_record))
                      MaterialBanner(
                        content: const Text(
                          'عملية بيع غير محسومة؛ تحقق قبل إصدار فاتورة أخرى.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: _reviewSale,
                            child: const Text('التحقق من العملية'),
                          ),
                        ],
                      ),
                    if (!widget.salesInvoice && !_service.workspaceAvailable)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'تحديث خادم الجملة مطلوب لتفعيل الحفظ والوظائف الجديدة.',
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _customerPanel(),
                                _catalog(),
                                _cartPanel(),
                                _summaryPanel(),
                                _paymentPanel(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_saving)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  'WaslaPOS',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
