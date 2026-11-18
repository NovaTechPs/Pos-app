part of 'pos_workspace.dart';

extension _ReferenceDesktop on _PosWorkspaceState {
  static const _blue = Color(0xFF2563EB);
  static const _line = Color(0xFFE2E8F0);
  static const _slate = Color(0xFF0F172A);

  Widget _referenceButton(
    String label,
    IconData icon,
    VoidCallback? action, {
    Color color = _blue,
    String? shortcut,
    bool outlined = false,
    double? width,
  }) {
    return SizedBox(
      key: ValueKey('pos-tool-$label'),
      width: width,
      height: 52,
      child: OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(
          foregroundColor: outlined ? color : Colors.white,
          backgroundColor: outlined ? color.withValues(alpha: .04) : color,
          disabledBackgroundColor: color.withValues(
            alpha: color == const Color(0xFFFB7C8B) ? .85 : .13,
          ),
          disabledForegroundColor: color == const Color(0xFFFB7C8B)
              ? Colors.white
              : const Color(0xFF94A3B8),
          side: BorderSide(
            color: outlined ? color.withValues(alpha: .2) : Colors.transparent,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 7),
              Text(label),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shortcut,
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _referencePill(
    String label,
    IconData icon, {
    Color color = const Color(0xFF475569),
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .05),
      border: Border.all(color: color.withValues(alpha: .17)),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    ),
  );

  Widget _matchedToolbar(bool ready) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 19),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReferenceToolbarRow(
          children: [
            _referenceButton(
              'بحث',
              Icons.search,
              widget.actions['بحث فاتورة'] ?? widget.actions['سجل الفواتير'],
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'السابقة',
              Icons.arrow_back,
              widget.actions['الفاتورة السابقة'],
              outlined: true,
              color: _slate,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'التالية',
              Icons.arrow_forward,
              widget.actions['الفاتورة التالية'],
              outlined: true,
              color: _slate,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'إضافة هدية',
              Icons.card_giftcard,
              widget.actions['إضافة هدية'],
              color: const Color(0xFFCA00DF),
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'حذف الفاتورة',
              Icons.delete_outline,
              widget.actions['حذف الفاتورة'],
              color: const Color(0xFFFB7C8B),
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'فاتورة جديدة',
              Icons.add_circle,
              widget.actions['فاتورة جديدة'] ?? widget.onClear,
              color: const Color(0xFF009D70),
            ),
            const SizedBox(width: 8),
            _referenceButton(
              widget.shiftId == null ? 'فتح الشيفت' : 'إغلاق الشيفت',
              Icons.lock,
              widget.actions[widget.shiftId == null
                  ? 'فتح وردية'
                  : 'إغلاق الوردية'],
              color: _slate,
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
              valueListenable: ApiClient.offline,
              builder: (_, offline, _) => _referenceButton(
                offline ? 'أوفلاين / Offline' : 'أونلاين / Online',
                offline ? Icons.cloud_off_outlined : Icons.circle,
                widget.actions['المزامنة'],
                color: offline
                    ? const Color(0xFFD97706)
                    : const Color(0xFF00B981),
                outlined: true,
              ),
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'مرتجع',
              Icons.undo,
              widget.actions['مرتجعات المبيعات'],
              outlined: true,
              color: _slate,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'التكلفة',
              Icons.diamond_outlined,
              widget.actions['التكلفة'],
              outlined: true,
              color: _slate,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'تعليق',
              Icons.restart_alt,
              ready ? widget.onHold : null,
              color: const Color(0xFFF4C749),
              shortcut: 'F2',
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'معلقة',
              Icons.receipt_long,
              widget.onHeld,
              color: const Color(0xFF1E293B),
              shortcut: 'F1',
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'الأصناف',
              Icons.inventory_2,
              widget.onProducts ?? () => widget.onCategory(null),
              shortcut: 'F10',
            ),
          ],
        ),
        const Divider(height: 16, color: Color(0xFFF1F5F9)),
        _ReferenceToolbarRow(
          children: [
            _referencePill(
              widget.editingInvoiceId != null
                  ? 'تعديل فاتورة #${widget.editingInvoiceId}'
                  : widget.cart.isEmpty
                  ? 'فاتورة جديدة جاهزة'
                  : 'فاتورة قيد الإدخال',
              Icons.circle,
              color: const Color(0xFF00B981),
            ),
            const SizedBox(width: 8),
            _referencePill(
              '${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
              Icons.calendar_today_outlined,
            ),
            const SizedBox(width: 8),
            _referencePill(widget.cashier, Icons.person),
            const SizedBox(width: 8),
            _referencePill(
              widget.shiftId == null
                  ? 'لا يوجد شيفت مفتوح'
                  : 'شيفت #${widget.shiftId} مفتوح',
              Icons.circle,
              color: const Color(0xFF00B981),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: widget.actions['ملاحظات'],
                icon: const Icon(Icons.edit_note, size: 17),
                label: const Text('ملاحظات', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'أدوات إضافية',
              onSelected: (label) => widget.actions[label]?.call(),
              itemBuilder: (_) => [
                for (final label in [
                  'خصم نسبة',
                  'تعديل الصافي',
                  'سجل الفواتير',
                  'تسجيل مصروف',
                  'سند قبض',
                  'كشف حساب العميل',
                  'إضافة عميل',
                  'إعادة طباعة آخر فاتورة',
                ])
                  if (widget.actions[label] != null)
                    PopupMenuItem(value: label, child: Text(label)),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'حفظ',
              Icons.save_outlined,
              ready ? widget.actions['حفظ'] : null,
              color: _slate,
              shortcut: 'F3',
              width: 156,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'حفظ وطباعة',
              Icons.print_outlined,
              ready ? widget.actions['حفظ وطباعة'] : null,
              color: _slate,
              shortcut: 'F6',
              width: 180,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'فاتورة جديدة',
              Icons.add,
              widget.actions['فاتورة جديدة'] ?? widget.onClear,
              outlined: true,
              color: const Color(0xFF64748B),
              shortcut: 'F4',
              width: 170,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'PDF',
              Icons.description_outlined,
              widget.actions['PDF'],
              color: const Color(0xFFDC2626),
              outlined: true,
              width: 150,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'نسخ',
              Icons.copy_outlined,
              widget.actions['نسخ'],
              color: const Color(0xFFA855F7),
              outlined: true,
              width: 170,
            ),
            const SizedBox(width: 8),
            _referenceButton(
              'واتساب',
              Icons.chat_bubble_outline,
              widget.actions['واتساب'],
              color: const Color(0xFF00B981),
              outlined: true,
              width: 170,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _referenceAmount(
    String label,
    String value, {
    Color color = const Color(0xFF475569),
    Color background = const Color(0xFFF8FAFC),
    Widget? field,
  }) => Expanded(
    child: Container(
      height: 110,
      margin: const EdgeInsetsDirectional.only(start: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.start,
            style: TextStyle(fontSize: 10, color: color),
          ),
          const SizedBox(height: 7),
          Expanded(
            child:
                field ??
                Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
          ),
        ],
      ),
    ),
  );

  Widget _referencePayment() => Container(
    key: const Key('pos-payment-footer'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 30,
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الزبون / المورد',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: CustomerPicker(
                    customers: widget.customers,
                    value: widget.customerId,
                    placeholder: 'إضافة زبون للفاتورة',
                    onRefresh: widget.onRefreshCustomers,
                    onChanged: widget.onCustomer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 22,
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'طريقة الدفع',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'اختر طريقة الدفع',
                  style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                ),
                const Spacer(),
                Row(
                  children: [
                    for (final method in const {
                      'cash': 'نقدي',
                      'card': 'بطاقة',
                      'bank_transfer': 'تحويل',
                      'cheque': 'شيك',
                    }.entries)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 5),
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              onPressed: () => widget.onPayment(method.key),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor:
                                    widget.paymentMethod == method.key
                                    ? _blue
                                    : Colors.white,
                                foregroundColor:
                                    widget.paymentMethod == method.key
                                    ? Colors.white
                                    : _slate,
                                side: const BorderSide(color: _line),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Text(
                                method.value,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          flex: 48,
          child: Row(
            children: [
              _referenceAmount('الإجمالي', _money(widget.subtotal)),
              _referenceAmount(
                'الخصم',
                _money(widget.discount),
                field: TextField(
                  controller: _discount,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    errorText: _discountError == null ? null : 'خصم غير صالح',
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                  ),
                  onChanged: (value) {
                    final amount = SaleData.number(value);
                    final valid =
                        amount != null &&
                        amount >= 0 &&
                        amount <= widget.subtotal;
                    _refreshDesktop(
                      () => _discountError = valid ? null : 'أدخل خصماً صالحاً',
                    );
                    widget.onDiscountValidity?.call(valid);
                    if (valid) widget.onDiscount(amount);
                  },
                ),
              ),
              _referenceAmount(
                'التوصيل',
                _money(widget.deliveryFee),
                field: TextButton(
                  onPressed: widget.actions['التوصيل'],
                  child: Text(_money(widget.deliveryFee)),
                ),
              ),
              _referenceAmount(
                'الصافي للدفع',
                _money(widget.total),
                color: const Color(0xFFD99A19),
                background: const Color(0xFFFFFBEB),
              ),
              _referenceAmount(
                'المدفوع',
                _money(_paidAmount),
                color: _blue,
                background: const Color(0xFFEFF6FF),
                field: TextField(
                  key: const Key('pos-paid-input'),
                  controller: _paid,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                  ),
                  onChanged: (_) {
                    _refreshDesktop(() {});
                    _notifyTender();
                  },
                ),
              ),
              _referenceAmount(
                'الباقي',
                _money((_paidAmount - widget.total).clamp(0, double.infinity)),
                color: const Color(0xFF009D70),
                background: const Color(0xFFECFDF5),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _referenceCatalog() => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الأصناف',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.products.length} صنف',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 35,
                    child: OutlinedButton(
                      onPressed: widget.actions['تحديث الأصناف'],
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        '↻ تحديث',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Focus(
                // Web: ↓ first result · Enter add/submit · Esc clear.
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.arrowDown) {
                    if (_deskProducts.isNotEmpty) {
                      _productsKeyboard.currentState?.selectFirst();
                    }
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.numpadEnter) {
                    _submitCatalogSearch();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.escape &&
                      _catalogSearch.text.isNotEmpty) {
                    _clearCatalogSearch();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const Key('pos-catalog-search'),
                  controller: _catalogSearch,
                  focusNode: widget.catalogFocus,
                  onChanged: _onCatalogSearch,
                  decoration: const InputDecoration(
                    hintText: 'اسم الصنف، أي كلمات منه، رقمه أو باركوده…',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'الكلمات بأي ترتيب · يدعم اختلافات الألف والياء والتشكيل',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'F2 بحث · ↓ اختيار · Enter إضافة · Esc مسح',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _referenceFilters(),
        Expanded(child: _referenceProductTable()),
      ],
    ),
  );

  Widget _referenceFilter(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: SizedBox(
          height: 34,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: selected ? _blue : Colors.white,
              foregroundColor: selected ? Colors.white : _slate,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: selected ? _blue : _line),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );

  /// Web shows only "الكل" and "عروض" above the product table.
  Widget _referenceFilters() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Row(
      children: [
        _referenceFilter('الكل', !_offersOnly, () => _showOffers(false)),
        _referenceFilter('عروض', _offersOnly, () => _showOffers(true)),
      ],
    ),
  );

  static const _rowExtent = 60.0;
  static const _rose = Color(0xFFE11D48);

  /// Web-style product table: one product per row, ↑/↓ move, Enter adds.
  Widget _referenceProductTable() {
    final products = _deskProducts;
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final extent = _rowExtent * scale;
    const headerStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        Container(
          key: const Key('pos-product-table-header'),
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: const Row(
            children: [
              Expanded(
                child: Text('الصنف / رقم الصنف / الباركود', style: headerStyle),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  'سعر البيع',
                  textAlign: TextAlign.center,
                  style: headerStyle,
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  'المتوفر',
                  textAlign: TextAlign.center,
                  style: headerStyle,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Text(
                    _offersOnly ? 'لا توجد عروض' : 'لا توجد منتجات مطابقة',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : PosProductKeyboard(
                  key: _productsKeyboard,
                  count: products.length,
                  columns: 1,
                  stride: extent,
                  leading: 0,
                  controller: _productsScroll,
                  onActivate: (index) {
                    if (!widget.busy && !widget.repricing) {
                      _selectProduct(
                        Map<String, dynamic>.from(products[index]),
                      );
                    }
                  },
                  builder: (node, selected, focused) => ListView.builder(
                    controller: _productsScroll,
                    itemExtent: extent,
                    itemCount: products.length,
                    itemBuilder: (context, index) => _referenceProductRow(
                      products[index],
                      index,
                      focused && selected == index,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _referenceProductRow(dynamic raw, int index, bool active) {
    final product = raw as Map;
    final price = widget.priceFor(product);
    final stock = StockPreview.quantities(product, widget.cart);
    final available = stock.total ?? stock.local;
    final soldOut = available != null && available <= 0;
    final barcode = '${product['barcode'] ?? ''}'.trim();
    final offerQuantity = SaleData.number(product['offer_quantity']) ?? 0;
    final offerPrice = SaleData.number(product['offer_price']);
    const muted = TextStyle(fontSize: 9.5, color: Color(0xFF64748B));
    return Material(
      key: ValueKey('pos-product-$index'),
      color: active
          ? const Color(0xFFEEF2FF)
          : soldOut
          ? const Color(0xFFFFF1F2)
          : Colors.white,
      child: InkWell(
        canRequestFocus: false,
        hoverColor: const Color(0xFFEEF2FF),
        onTap: widget.busy || widget.repricing
            ? null
            : () => _selectProduct(Map<String, dynamic>.from(product)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: active
                ? Border.all(color: const Color(0xFF6366F1), width: 2)
                : const Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product['name']?.toString() ?? 'منتج',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _slate,
                            ),
                          ),
                        ),
                        if (soldOut) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4E6),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'نافد',
                              style: TextStyle(fontSize: 9, color: _rose),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'رقم: ${product['product_number'] ?? product['id'] ?? '—'}'
                      '    باركود: ${barcode.isEmpty ? '—' : barcode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                    if (offerQuantity > 0 && offerPrice != null)
                      Text(
                        'عرض ${_quantity(offerQuantity)} بـ ${_money(offerPrice)}',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  price == null ? 'غير مسعّر' : _money(price),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: price == null ? _rose : _blue,
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: soldOut
                          ? const Color(0xFFFFE4E6)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stockLabel(product),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: soldOut ? _rose : _slate,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchedDesktop() {
    final ready =
        widget.cart.isNotEmpty && _discountError == null && _tenderValid;
    return AbsorbPointer(
      absorbing: widget.busy || widget.repricing,
      child: ColoredBox(
        color: const Color(0xFFF1F5F9),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            children: [
              _matchedToolbar(ready),
              const SizedBox(height: 8),
              if (widget.busy || widget.repricing)
                const LinearProgressIndicator(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 32, child: _referenceCatalog()),
                    const SizedBox(width: 10),
                    Expanded(flex: 68, child: _desktopInvoice()),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _referencePayment(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceToolbarRow extends StatelessWidget {
  const _ReferenceToolbarRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => SizedBox(
      height: 52,
      width: constraints.maxWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: children,
          ),
        ),
      ),
    ),
  );
}
