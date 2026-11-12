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
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _productsKeyboard.currentState?.selectFirst();
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _catalog(),
          ),
        ),
      ],
    ),
  );

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
