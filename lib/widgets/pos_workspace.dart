import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stock_preview.dart';

import 'package:flutter/services.dart';

import 'pos_keyboard.dart';
import 'pos_product_keyboard.dart';

import '../models/sale_data.dart';
import 'customer_picker.dart';
import 'product_add_dialog.dart';
import '../models/product_catalog.dart';
import '../services/api_client.dart';
import '../services/barcode_service.dart';

part 'pos_desktop.dart';

/// Shared POS layout: catalog and cart use the same controls at every width.
class PosWorkspace extends StatefulWidget {
  const PosWorkspace({
    super.key,
    required this.products,
    required this.categories,
    required this.customers,
    required this.cart,
    required this.barcodeController,
    required this.barcodeFocus,
    required this.selectedCategoryId,
    required this.customerId,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paymentMethod,
    required this.cashier,
    required this.shiftId,
    required this.priceFor,
    required this.onBarcode,
    required this.onSubmitBarcode,
    required this.onScan,
    required this.onCategory,
    required this.onCustomer,
    this.onRefreshCustomers,
    required this.onAdd,
    required this.onQuantity,
    required this.onRemove,
    required this.onDiscount,
    required this.onPayment,
    required this.onCheckout,
    required this.onHold,
    required this.onHeld,
    required this.onClear,
    required this.actions,
    this.embedded = false,
    this.mergeSimilar = true,
    this.onMergeSimilar,
    this.busy = false,
    this.repricing = false,
    this.onDiscountValidity,
    this.onTenderValidity,
    this.onProducts,
    this.catalogFocus,
    this.onEditLine,
    this.deliveryFee = 0,
    this.editingInvoiceId,
    this.notice,
    this.onLineValue,
    this.onMobileAdd,
    this.addedLine = -1,
    this.addCount = 0,
    this.onInvoiceSearch,
    this.recipientName = '',
    this.onRecipientName,
  });

  /// Desktop toolbar search: opens a saved invoice by number or ID, like the web POS.
  final ValueChanged<String>? onInvoiceSearch;

  /// Web «اسم المستلم على الفاتورة»: the name printed on the invoice; empty means the customer's name.
  final String recipientName;
  final ValueChanged<String>? onRecipientName;

  /// Index of the line just added and a counter bumped on every add; the
  /// desktop invoice table scrolls to that line each time.
  final int addedLine, addCount;

  final List<dynamic> products, categories, customers;
  final List<Map<String, dynamic>> cart;
  final TextEditingController barcodeController;
  final FocusNode barcodeFocus;
  final FocusNode? catalogFocus;
  final int? selectedCategoryId, customerId;
  final Object? shiftId;
  final double subtotal, discount, tax, total;
  final double deliveryFee;
  final int? editingInvoiceId;
  final String paymentMethod, cashier;
  final bool busy, repricing;
  final bool embedded, mergeSimilar;
  final ValueChanged<bool>? onMergeSimilar;
  final double? Function(dynamic) priceFor;
  final ValueChanged<String> onBarcode, onSubmitBarcode, onPayment;
  final ValueChanged<int?> onCategory, onCustomer;
  final Future<List<dynamic>> Function()? onRefreshCustomers;
  final bool Function(Map<String, dynamic>) onAdd;
  final Future<void> Function(Map<String, dynamic>)? onMobileAdd;
  final void Function(int, int) onQuantity;
  final ValueChanged<int> onRemove;
  final ValueChanged<int>? onEditLine;
  final ValueChanged<double> onDiscount;
  final ValueChanged<bool>? onDiscountValidity, onTenderValidity;
  final VoidCallback onScan, onCheckout, onHold, onHeld, onClear;
  final VoidCallback? onProducts;
  final String? notice;
  final void Function(int, String, double)? onLineValue;
  final Map<String, VoidCallback> actions;

  @override
  State<PosWorkspace> createState() => _PosWorkspaceState();
}

class _PosWorkspaceState extends State<PosWorkspace> {
  String _stockLabel(Map product, {bool project = false}) {
    final stock = StockPreview.quantities(
      product,
      widget.cart,
      project: project && widget.editingInvoiceId == null,
    );
    final local = stock.local == null ? '—' : _quantity(stock.local);
    return stock.total == null ? local : '$local / ${_quantity(stock.total)}';
  }

  final _cartKeyboard = PosCartKeyboard();
  final _invoiceScroll = ScrollController();
  final _lineKeys = <int, GlobalKey>{};
  GlobalKey _lineKey(int index) =>
      _lineKeys.putIfAbsent(index, () => GlobalKey());

  /// Scrolls the invoice table so the just-added line is visible (a new
  /// line ends up at the bottom, a merged line stays where it is).
  void _revealAddedLine() {
    final index = widget.addedLine;
    final context = _lineKeys[index]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    } else if (_invoiceScroll.hasClients) {
      _invoiceScroll.animateTo(
        _invoiceScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  final _productsKeyboard = GlobalKey<PosProductKeyboardState>();
  final _productsScroll = ScrollController();
  Widget _numberCell(int row, int col, double value, {PosCellLook? look}) =>
      PosNumberCell(
        key: ValueKey('pos-cart-$row-$col'),
        value: value,
        look: look,
        node: _cartKeyboard.node(row, col),
        quantity: col == 0,
        readOnly: col != 0 && widget.cart[row]['gift'] == true,
        onKey: (event) => _cartKeyboard.handle(
          event,
          row,
          col,
          widget.cart.length,
          widget.barcodeFocus,
        ),
        onValue: (value) => widget.onLineValue?.call(
          row,
          ['quantity', 'price', 'subtotal'][col],
          value,
        ),
      );
  bool _showCart = false;
  String _catalogQuery = '';
  final _catalogSearch = TextEditingController();
  Timer? _catalogSearchDebounce;
  void _onCatalogSearch(String value) {
    _catalogSearchDebounce?.cancel();
    if (value.isEmpty) {
      setState(() => _catalogQuery = '');
    } else {
      _catalogSearchDebounce = Timer(const Duration(milliseconds: 90), () {
        if (mounted) setState(() => _catalogQuery = value);
      });
    }
  }

  void _selectProduct(Map<String, dynamic> product) {
    if (widget.busy || widget.repricing || !widget.onAdd(product)) return;
    _catalogSearchDebounce?.cancel();
    _catalogSearch.clear();
    setState(() => _catalogQuery = '');
    if (widget.selectedCategoryId != null) widget.onCategory(null);
    widget.barcodeFocus.requestFocus();
  }

  final _paid = TextEditingController();
  bool get _tenderValid =>
      widget.paymentMethod != 'cash' ||
      _paid.text.trim().isEmpty ||
      (SaleData.number(_paid.text) != null && _paidAmount >= widget.total);
  void _notifyTender() => widget.onTenderValidity?.call(_tenderValid);
  double get _paidAmount => SaleData.number(_paid.text) ?? widget.total;
  List<dynamic>? _filteredProducts, _filterSource;
  String? _filterQuery;
  ProductCatalog? _filterIndex;
  List<dynamic> get _visibleProducts {
    final query = ProductCatalog.normalizeSearch(_catalogQuery);
    if (query.isEmpty) return widget.products;
    if (identical(_filterSource, widget.products) && query == _filterQuery) {
      return _filteredProducts!;
    }
    if (!identical(_filterSource, widget.products)) {
      _filterSource = widget.products;
      _filterIndex = ProductCatalog([
        {'products': widget.products},
      ]);
    }
    _filterQuery = query;
    return _filteredProducts = _filterIndex!.search(query, null);
  }

  /// Desktop "عروض" filter, as on the web POS.
  bool _offersOnly = false;
  static bool _hasOffer(dynamic product) =>
      (SaleData.number(product['offer_quantity']) ?? 0) > 0 &&
      SaleData.number(product['offer_price']) != null;
  List<dynamic>? _offerSource, _offerProducts;

  /// Web «سعر البيع — اختياري»: only products sold at this price in the branch.
  final _priceFilter = TextEditingController();
  double? _priceQuery;
  final _invoiceSearch = TextEditingController();
  late final _recipient = TextEditingController(text: widget.recipientName);
  List<dynamic>? _priceSource, _priceProducts;
  double? _pricedFor;
  List<dynamic> get _deskProducts {
    var products = _visibleProducts;
    if (_offersOnly) {
      if (!identical(_offerSource, products)) {
        _offerSource = products;
        _offerProducts = products.where(_hasOffer).toList(growable: false);
      }
      products = _offerProducts!;
    }
    final price = _priceQuery;
    if (price == null) return products;
    if (!identical(_priceSource, products) || _pricedFor != price) {
      _priceSource = products;
      _pricedFor = price;
      _priceProducts = products
          .where((product) {
            final value = widget.priceFor(product);
            return value != null && (value - price).abs() < .005;
          })
          .toList(growable: false);
    }
    return _priceProducts!;
  }

  void _onPriceFilter(String value) {
    final price = value.trim().isEmpty ? null : SaleData.number(value);
    if (price != _priceQuery) setState(() => _priceQuery = price);
  }

  /// Web: Enter in the search adds an exact barcode/number match or the only
  /// result; otherwise it moves to the first result.
  void _submitCatalogSearch() {
    _catalogSearchDebounce?.cancel();
    final text = _catalogSearch.text.trim();
    if (_catalogQuery != text) setState(() => _catalogQuery = text);
    final products = _deskProducts;
    if (text.isEmpty || products.isEmpty) return;
    final code = BarcodeService.normalize(text);
    final exact = products.where(
      (product) =>
          BarcodeService.codes(product).contains(code) ||
          BarcodeService.normalize(product['product_number']) == code,
    );
    final match = exact.length == 1
        ? exact.single
        : products.length == 1
        ? products.single
        : null;
    if (match != null) {
      _selectProduct(Map<String, dynamic>.from(match));
    } else {
      _productsKeyboard.currentState?.selectFirst();
    }
  }

  void _showOffers(bool value) {
    setState(() => _offersOnly = value);
    if (widget.selectedCategoryId != null) widget.onCategory(null);
  }

  void _clearCatalogSearch() {
    _catalogSearchDebounce?.cancel();
    _catalogSearch.clear();
    setState(() => _catalogQuery = '');
  }

  bool _keyboardEnabled = false;
  final _discount = TextEditingController();

  /// No discount shows an empty field with the hint «0», as on the web POS.
  String _discountText(double value) =>
      value == 0 ? '' : value.toStringAsFixed(2);
  String? _discountError;

  @override
  void initState() {
    super.initState();
    _discount.text = _discountText(widget.discount);
  }

  @override
  void didUpdateWidget(PosWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new or reopened invoice brings its own recipient name.
    if (widget.recipientName != _recipient.text) {
      _recipient.text = widget.recipientName;
    }
    if (oldWidget.addCount != widget.addCount && widget.addedLine >= 0) {
      // After this frame lays out the new line.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealAddedLine();
      });
    }
    if (!identical(oldWidget.products, widget.products)) {
      _filterSource = null;
      _filterIndex = null;
      _filteredProducts = null;
      _filterQuery = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyTender();
    });
    if (oldWidget.discount != widget.discount &&
        SaleData.number(_discount.text) != widget.discount) {
      _discount.text = _discountText(widget.discount);
      _discountError = null;
    }
    if (widget.subtotal < (SaleData.number(_discount.text) ?? 0)) {
      _discountError = 'الخصم يتجاوز قيمة الأصناف';
    }
    if (widget.cart.isEmpty) {
      _paid.clear();
      _discount.text = '';
      _discountError = null;
    }
  }

  @override
  void dispose() {
    _cartKeyboard.dispose();
    _invoiceScroll.dispose();
    _productsScroll.dispose();
    _catalogSearchDebounce?.cancel();
    _catalogSearch.dispose();
    _paid.dispose();
    _discount.dispose();
    _priceFilter.dispose();
    _invoiceSearch.dispose();
    _recipient.dispose();
    super.dispose();
  }

  String _money(double value) => value.toStringAsFixed(2);
  String _quantity(Object? raw) {
    final value = SaleData.number(raw) ?? 0;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  Widget _catalog() => Column(
    children: [
      if (MediaQuery.sizeOf(context).width < 1050)
        TextField(
          key: const Key('pos-catalog-search'),
          controller: _catalogSearch,
          focusNode: widget.catalogFocus,
          onChanged: _onCatalogSearch,
          decoration: InputDecoration(
            hintText: 'ابحث عن الصنف أو الباركود…',
            suffixIcon: IconButton(
              onPressed: widget.onScan,
              tooltip: 'مسح الباركود',
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
        ),
      SizedBox(
        height: MediaQuery.sizeOf(context).width >= 1050 ? 64 : 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: const Text('الكل'),
                selected: widget.selectedCategoryId == null,
                onSelected: (_) => widget.onCategory(null),
              ),
            ),
            ...widget.categories.map(
              (category) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(category['name']?.toString() ?? 'قسم'),
                  selected:
                      SaleData.id(category['id']) == widget.selectedCategoryId,
                  onSelected: (_) =>
                      widget.onCategory(SaleData.id(category['id'])),
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: _visibleProducts.isEmpty
            ? const Center(child: Text('لا توجد منتجات مطابقة'))
            : MediaQuery.sizeOf(context).width < 1050
            ? ListView.builder(
                itemCount: _visibleProducts.length,
                itemBuilder: (context, index) {
                  final product = Map<String, dynamic>.from(
                    _visibleProducts[index],
                  );
                  return MobileProductRow(
                    key: ValueKey('pos-product-$index'),
                    product: product,
                    price: widget.priceFor(product),
                    onTap: widget.busy || widget.repricing
                        ? null
                        : () {
                            if (widget.onMobileAdd != null) {
                              widget.onMobileAdd!(product);
                            } else {
                              _selectProduct(product);
                            }
                          },
                  );
                },
              )
            : LayoutBuilder(
                builder: (context, constraints) => PosProductKeyboard(
                  key: _productsKeyboard,
                  count: _visibleProducts.length,
                  columns: ((constraints.maxWidth + 10) / 230).ceil().clamp(
                    1,
                    100,
                  ),
                  stride:
                      (MediaQuery.sizeOf(context).width >= 1050 ? 98 : 160) *
                          math.max(
                            1,
                            MediaQuery.textScalerOf(context).scale(1),
                          ) +
                      10,
                  controller: _productsScroll,
                  onActivate: (index) {
                    if (!widget.busy && !widget.repricing) {
                      _selectProduct(
                        Map<String, dynamic>.from(_visibleProducts[index]),
                      );
                    }
                  },
                  builder: (node, selected, focused) => GridView.builder(
                    controller: _productsScroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisExtent:
                          (MediaQuery.sizeOf(context).width >= 1050
                              ? 98
                              : 160) *
                          math.max(
                            1,
                            MediaQuery.textScalerOf(context).scale(1),
                          ),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _visibleProducts.length,
                    itemBuilder: (context, index) {
                      final product = _visibleProducts[index];
                      final price = widget.priceFor(product);
                      return Card(
                        key: ValueKey('pos-product-$index'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: focused && selected == index
                                ? const Color(0xFF2563EB)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          canRequestFocus: false,
                          onTap: () => _selectProduct(
                            Map<String, dynamic>.from(product),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  product['name']?.toString() ?? 'منتج',
                                  textAlign: TextAlign.start,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        price == null
                                            ? 'غير مسعّر'
                                            : _money(price),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: price == null
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                        ),
                                      ),
                                    ),
                                    if (product['stock_quantity'] != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (SaleData.number(
                                                        product['stock_quantity'],
                                                      ) ??
                                                      0) >
                                                  0
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFFFF1F2),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          _stockLabel(product),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color:
                                                (SaleData.number(
                                                          product['stock_quantity'],
                                                        ) ??
                                                        0) >
                                                    0
                                                ? const Color(0xFF047857)
                                                : const Color(0xFFE11D48),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  'رقم المنتج: ${product['product_number'] ?? product['id'] ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    ],
  );

  Widget _amount(String title, double amount, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          '${_money(amount)} ر.س',
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: bold ? 20 : 14,
          ),
        ),
      ],
    ),
  );

  Widget _cart() => LayoutBuilder(
    builder: (context, constraints) {
      final minimumHeight =
          470.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
      if (constraints.maxHeight < minimumHeight) {
        return SingleChildScrollView(
          child: SizedBox(height: minimumHeight, child: _cartPanel()),
        );
      }
      return _cartPanel();
    },
  );

  Widget _cartPanel() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الفاتورة • ${widget.cart.length} أصناف',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: widget.cart.isEmpty ? null : widget.onClear,
                tooltip: 'إفراغ السلة',
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: widget.cart.isEmpty
                ? const Center(
                    child: Text(
                      'الفاتورة فارغة\nامسح الباركود أو اختر صنفاً',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: widget.cart.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = widget.cart[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "${item['name'] ?? 'منتج'}${item['gift'] == true ? ' — هدية' : ''}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'المتبقي: ${_stockLabel(item, project: true)}',
                            textDirection: TextDirection.rtl,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_money(SaleData.lineTotal(item))} ر.س',
                                ),
                              ),
                              IconButton(
                                onPressed: () => widget.onQuantity(index, -1),
                                tooltip: 'تقليل الكمية',
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Flexible(
                                child: InkWell(
                                  key: ValueKey('pos-edit-line-$index'),
                                  onTap: widget.onEditLine == null
                                      ? null
                                      : () => widget.onEditLine!(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(_quantity(item['quantity'])),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => widget.onQuantity(index, 1),
                                tooltip: 'زيادة الكمية',
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              IconButton(
                                onPressed: () => widget.onRemove(index),
                                tooltip: 'حذف الصنف',
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(),
          _amount('قيمة الأصناف', widget.subtotal),
          if (widget.tax != 0) _amount('الضريبة', widget.tax),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'خصم الفاتورة',
                    hintText: '0',
                    errorText: _discountError,
                    isDense: true,
                  ),
                  onChanged: (value) {
                    final discount = value.trim().isEmpty
                        ? 0.0
                        : SaleData.number(value);
                    final valid =
                        discount != null &&
                        discount >= 0 &&
                        discount <= widget.subtotal;
                    setState(
                      () => _discountError = valid ? null : 'أدخل خصماً صالحاً',
                    );
                    widget.onDiscountValidity?.call(valid);
                    if (valid) widget.onDiscount(discount);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(widget.paymentMethod),
                  initialValue: widget.paymentMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'وسيلة الدفع',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                    DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text('تحويل'),
                    ),
                    DropdownMenuItem(value: 'cheque', child: Text('شيك')),
                  ],
                  onChanged: (value) {
                    if (value != null) widget.onPayment(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _amount('الإجمالي', widget.total, bold: true),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: widget.onHeld,
                tooltip: 'الفواتير المعلقة',
                icon: const Icon(Icons.receipt_long),
              ),
              IconButton(
                onPressed: widget.cart.isEmpty || _discountError != null
                    ? null
                    : widget.onHold,
                tooltip: 'تعليق الفاتورة',
                icon: const Icon(Icons.pause_circle_outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.cart.isEmpty || _discountError != null
                      ? null
                      : widget.onCheckout,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('إتمام البيع'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _refreshDesktop(VoidCallback update) => setState(update);

  Widget _desktop() => _matchedDesktop();

  Widget _desktopInvoice() => _webInvoice();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 1050;
      if (!compact) {
        return Focus(
          onKeyEvent: (_, event) {
            if (!widget.busy &&
                !widget.repricing &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowUp &&
                widget.barcodeFocus.hasFocus &&
                widget.cart.isNotEmpty &&
                ModalRoute.of(context)?.isCurrent == true) {
              _cartKeyboard.focus(widget.cart.length - 1, 0);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _desktop(),
        );
      }
      final keyboardOpen =
          compact && MediaQuery.viewInsetsOf(context).bottom > 0;
      return AbsorbPointer(
        absorbing: widget.busy || widget.repricing,
        child: Column(
          children: [
            if (widget.busy || widget.repricing)
              const LinearProgressIndicator(),
            if (!keyboardOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'رجوع',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.editingInvoiceId == null
                                ? 'نقطة البيع • ${widget.cashier}'
                                : 'تعديل فاتورة #${widget.editingInvoiceId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            widget.shiftId == null
                                ? 'لا توجد وردية مفتوحة'
                                : 'وردية #${widget.shiftId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'فتح قسم',
                      onSelected: (value) => widget.actions[value]?.call(),
                      itemBuilder: (_) => widget.actions.keys
                          .map(
                            (label) =>
                                PopupMenuItem(value: label, child: Text(label)),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('pos-barcode-input'),
                          controller: widget.barcodeController,
                          focusNode: widget.barcodeFocus,
                          keyboardType: _keyboardEnabled
                              ? TextInputType.text
                              : TextInputType.none,
                          onEditingComplete: () {},
                          onChanged: widget.onBarcode,
                          onSubmitted: widget.onSubmitBarcode,
                          decoration: InputDecoration(
                            hintText: 'امسح أو أدخل باركود المنتج',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: 'إظهار أو إخفاء لوحة المفاتيح',
                              icon: const Icon(Icons.keyboard),
                              onPressed: () {
                                setState(
                                  () => _keyboardEnabled = !_keyboardEnabled,
                                );
                                widget.barcodeFocus.requestFocus();
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: widget.onScan,
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'مسح بالكاميرا',
                      ),
                    ],
                  ),
                  if (!keyboardOpen) const SizedBox(height: 8),
                  if (!keyboardOpen)
                    CustomerPicker(
                      customers: widget.customers,
                      value: widget.customerId,
                      label: 'الزبون / المورد والتسعير',
                      onRefresh: widget.onRefreshCustomers,
                      onChanged: widget.onCustomer,
                    ),
                ],
              ),
            ),
            if (compact && !keyboardOpen)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(
                      value: false,
                      label: Text('الأصناف'),
                      icon: Icon(Icons.grid_view),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('السلة (${widget.cart.length})'),
                      icon: const Icon(Icons.shopping_bag_outlined),
                    ),
                  ],
                  selected: {_showCart},
                  onSelectionChanged: (selection) =>
                      setState(() => _showCart = selection.first),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: compact
                    ? (_showCart ? _cart() : _catalog())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: _catalog()),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: _cart()),
                        ],
                      ),
              ),
            ),
            if (compact && !_showCart && !keyboardOpen)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'الأصناف المضافة: ${widget.cart.length}\n₪ ${_money(widget.total)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onHeld,
                        tooltip: 'الفواتير المعلقة',
                        icon: const Icon(Icons.receipt_long),
                      ),
                      IconButton(
                        onPressed: widget.cart.isEmpty || _discountError != null
                            ? null
                            : widget.onHold,
                        tooltip: 'تعليق الفاتورة',
                        icon: const Icon(Icons.pause_circle_outline),
                      ),
                      FilledButton(
                        onPressed: () => setState(() => _showCart = true),
                        child: const Text('عرض الفاتورة'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
