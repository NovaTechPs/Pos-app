part of 'pos_workspace.dart';

/// Colors, fonts and sizes of the web POS (Tailwind), so the Windows POS looks the same.
abstract final class _Web {
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const blue50 = Color(0xFFEFF6FF);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);
  static const blue800 = Color(0xFF1E40AF);
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo700 = Color(0xFF4338CA);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const green50 = Color(0xFFF0FDF4);
  static const green200 = Color(0xFFBBF7D0);
  static const green700 = Color(0xFF15803D);
  static const red50 = Color(0xFFFEF2F2);
  static const red200 = Color(0xFFFECACA);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber300 = Color(0xFFFCD34D);
  static const amber700 = Color(0xFFB45309);
  static const violet50 = Color(0xFFF5F3FF);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet700 = Color(0xFF6D28D9);
  static const fuchsia600 = Color(0xFFC026D3);

  /// The web POS sets Tahoma on its controls and the browser's monospace (Consolas) on numbers.
  static const font = 'Tahoma';
  static const mono = 'Consolas';

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = slate800,
    bool mono = false,
  }) => TextStyle(
    fontFamily: mono ? _Web.mono : font,
    // The toolbar glyphs (🎁 🔒 📦 💵 …) come from the Windows emoji font, as in the browser.
    fontFamilyFallback: const ['Segoe UI Emoji'],
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.25,
  );

  static const weekdays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  /// «الثلاثاء، 2026-11-24», as the web POS shows the date.
  static String date(DateTime day) =>
      '${weekdays[day.weekday - 1]}، ${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static InputDecoration field({
    String? hint,
    Color fill = Colors.white,
    Color border = slate200,
    double borderWidth = .8,
    double radius = 12,
    Color hintColor = slate400,
    double hintSize = 14,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 9,
    ),
  }) {
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: fill,
      hintText: hint,
      hintStyle: text(hintSize, color: hintColor),
      contentPadding: padding,
      border: outline(border, borderWidth),
      enabledBorder: outline(border, borderWidth),
      disabledBorder: outline(border, borderWidth),
      focusedBorder: outline(blue500, 1.6),
    );
  }

  /// hsl(hue 72% 96%) and friends, from the web «لون لكل صنف» invoice lines.
  static Color hsl(double hue, double saturation, double lightness) =>
      HSLColor.fromAHSL(1, hue % 360, saturation, lightness).toColor();
}

extension _ReferenceDesktop on _PosWorkspaceState {
  static const _blue = _Web.blue600;
  static const _line = _Web.slate200;
  static const _slate = _Web.slate900;

  /// One web toolbar button: an optional glyph, the label and an optional key badge.
  Widget _webButton(
    String label, {
    required VoidCallback? onTap,
    String? icon,
    Widget? iconWidget,
    String? trailing,
    String? shortcut,
    String? sub,
    Color background = _Web.blue600,
    Color foreground = Colors.white,
    Color? border,
    double height = 42,
    double fontSize = 12,
    Color? disabledBackground,
    Color? disabledForeground,
    bool twoLines = false,
    int? flex,
  }) {
    final enabled = onTap != null;
    final fill = enabled ? background : (disabledBackground ?? background);
    final ink = enabled ? foreground : (disabledForeground ?? foreground);
    final kbd = shortcut == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: ink == Colors.white
                  ? Colors.black.withValues(alpha: .22)
                  : _Web.slate800.withValues(alpha: enabled ? 1 : .35),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              shortcut,
              style: _Web.text(
                twoLines ? 8 : 9,
                weight: FontWeight.w900,
                color: Colors.white,
                mono: true,
              ),
            ),
          );
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconWidget != null) ...[iconWidget, const SizedBox(width: 6)],
        if (icon != null) ...[
          Text(icon, style: _Web.text(fontSize + 1, color: ink)),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: _Web.text(fontSize, weight: FontWeight.w900, color: ink),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(trailing, style: _Web.text(fontSize + 1, color: ink)),
        ],
        if (!twoLines && kbd != null) ...[const SizedBox(width: 8), kbd],
      ],
    );
    final content = twoLines || sub != null
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              const SizedBox(height: 4),
              if (sub != null)
                Text(
                  sub,
                  style: _Web.text(
                    8,
                    weight: FontWeight.w700,
                    color: ink.withValues(alpha: .8),
                  ),
                )
              else
                ?kbd,
            ],
          )
        : title;
    final button = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border == null
            ? BorderSide.none
            : BorderSide(color: border, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            ),
          ),
        ),
      ),
    );
    final keyed = KeyedSubtree(
      key: ValueKey('pos-tool-$label'),
      child: enabled || disabledBackground != null
          ? button
          : Opacity(opacity: .45, child: button),
    );
    // The first toolbar row shares its width in the web proportions, so it always fits.
    return flex == null ? keyed : Expanded(flex: flex, child: keyed);
  }

  Widget _webPill(
    String label, {
    String? icon,
    bool dot = false,
    Color background = _Web.slate50,
    Color border = _Web.slate200,
    Color foreground = _Web.slate600,
    FontWeight weight = FontWeight.w700,
  }) => Container(
    height: 29,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border, width: .8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: foreground == _Web.emerald700
                  ? _Web.emerald500
                  : _Web.rose500,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (icon != null) ...[
          Text(icon, style: _Web.text(10, color: foreground)),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: _Web.text(10, weight: weight, color: foreground),
        ),
      ],
    ),
  );

  void _searchInvoice() {
    final query = _invoiceSearch.text.trim();
    if (query.isNotEmpty && widget.onInvoiceSearch != null) {
      widget.onInvoiceSearch!(query);
      _invoiceSearch.clear();
    } else {
      (widget.actions['بحث فاتورة'] ?? widget.actions['سجل الفواتير'])?.call();
    }
  }

  Widget _matchedToolbar(bool ready) {
    const gap = SizedBox(width: 8);
    final shiftOpen = widget.shiftId != null;
    final hasLines = widget.cart.isNotEmpty;
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line, width: .8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                Expanded(
                  flex: 242,
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      key: const Key('pos-invoice-search'),
                      controller: _invoiceSearch,
                      style: _Web.text(14, color: _Web.slate700),
                      decoration: _Web.field(
                        hint: 'ابحث برقم الفاتورة أو ID...',
                        fill: _Web.slate50,
                      ),
                      onSubmitted: (_) => _searchInvoice(),
                    ),
                  ),
                ),
                gap,
                _webButton(
                  'بحث',
                  onTap: _searchInvoice,
                  trailing: '⌕',
                  flex: 72,
                ),
                gap,
                _webButton(
                  'السابقة',
                  flex: 81,
                  onTap: widget.actions['الفاتورة السابقة'],
                  trailing: '←',
                  fontSize: 10,
                  background: Colors.white,
                  foreground: _Web.slate700,
                  border: _line,
                ),
                gap,
                _webButton(
                  'التالية',
                  flex: 71,
                  onTap: widget.actions['الفاتورة التالية'],
                  trailing: '→',
                  fontSize: 10,
                  background: Colors.white,
                  foreground: _Web.slate700,
                  border: _line,
                ),
                gap,
                _webButton(
                  'إضافة هدية',
                  flex: 116,
                  onTap: widget.actions['إضافة هدية'],
                  icon: '🎁',
                  background: _Web.fuchsia600,
                ),
                gap,
                _webButton(
                  'حذف الفاتورة',
                  flex: 105,
                  onTap: widget.actions['حذف الفاتورة'],
                  sub: 'اختر فاتورة محفوظة',
                  background: _Web.red600,
                ),
                gap,
                _webButton(
                  'فاتورة جديدة',
                  flex: 130,
                  onTap: widget.actions['فاتورة جديدة'] ?? widget.onClear,
                  iconWidget: const Icon(
                    Icons.add_circle,
                    size: 18,
                    color: Colors.white,
                  ),
                  background: _Web.emerald600,
                ),
                if (shiftOpen && widget.actions['تسجيل مصروف'] != null) ...[
                  gap,
                  _webButton(
                    'مصروف من الصندوق',
                    flex: 169,
                    onTap: widget.actions['تسجيل مصروف'],
                    icon: '−',
                    background: _Web.rose600,
                  ),
                ],
                gap,
                _webButton(
                  shiftOpen ? 'إغلاق الشيفت' : 'فتح الشيفت',
                  flex: 138,
                  onTap:
                      widget.actions[shiftOpen ? 'إغلاق الوردية' : 'فتح وردية'],
                  icon: shiftOpen ? '🔒' : '🔓',
                  background: shiftOpen ? _slate : _Web.emerald600,
                ),
                gap,
                ValueListenableBuilder<bool>(
                  valueListenable: ApiClient.offline,
                  builder: (_, offline, _) => _webButton(
                    offline ? 'أوفلاين / Offline' : 'Online / أونلاين',
                    flex: 119,
                    onTap: widget.actions['المزامنة'] ?? () {},
                    iconWidget: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: offline
                            ? const Color(0xFFF59E0B)
                            : _Web.emerald500,
                        shape: BoxShape.circle,
                      ),
                    ),
                    background: offline ? _Web.amber50 : _Web.emerald50,
                    foreground: offline ? _Web.amber700 : _Web.emerald700,
                    border: offline ? _Web.amber200 : _Web.emerald200,
                  ),
                ),
                gap,
                _webButton(
                  'مرتجع',
                  flex: 88,
                  onTap: widget.actions['مرتجعات المبيعات'],
                  icon: '↩',
                  background: Colors.white,
                  foreground: _Web.slate700,
                  border: _line,
                ),
                gap,
                _webButton(
                  'التكلفة',
                  flex: 94,
                  onTap: hasLines ? widget.actions['التكلفة'] : null,
                  icon: '◇',
                  background: _Web.blue50,
                  foreground: _Web.blue700,
                  border: _Web.blue200,
                ),
                gap,
                _webButton(
                  'تعليق',
                  flex: 117,
                  onTap: ready ? widget.onHold : null,
                  icon: '↻',
                  shortcut: 'F2',
                  background: _Web.amber300,
                  foreground: _slate,
                  border: _Web.amber300,
                ),
                gap,
                _webButton(
                  'معلقة',
                  flex: 96,
                  onTap: widget.onHeld,
                  shortcut: 'F1',
                  background: _Web.slate800,
                ),
                gap,
                _webButton(
                  'الأصناف',
                  flex: 138,
                  onTap: widget.onProducts ?? () => widget.onCategory(null),
                  icon: '📦',
                  shortcut: 'F10',
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 45,
            child: Row(
              children: [
                // Pills, notes and more: shrink together when the window is narrow.
                Flexible(
                  flex: 590,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _webPill(
                          widget.editingInvoiceId != null
                              ? 'تعديل فاتورة #${widget.editingInvoiceId}'
                              : hasLines
                              ? 'فاتورة قيد الإدخال'
                              : 'فاتورة جديدة جاهزة',
                          dot: true,
                          background: _Web.emerald50,
                          border: _Web.emerald200,
                          foreground: _Web.emerald700,
                          weight: FontWeight.w900,
                        ),
                        gap,
                        _webPill(_Web.date(today), icon: '📅'),
                        gap,
                        _webPill(widget.cashier, icon: '👤'),
                        gap,
                        shiftOpen
                            ? _webPill(
                                'شيفت #${widget.shiftId} مفتوح',
                                dot: true,
                                background: _Web.emerald50,
                                border: _Web.emerald200,
                                foreground: _Web.emerald700,
                                weight: FontWeight.w900,
                              )
                            : _webPill(
                                'لا يوجد شيفت مفتوح',
                                dot: true,
                                background: _Web.rose50,
                                border: _Web.rose200,
                                foreground: _Web.rose700,
                                weight: FontWeight.w900,
                              ),
                        gap,
                        _webButton(
                          'ملاحظات',
                          onTap: widget.actions['ملاحظات'],
                          icon: '📝',
                          height: 34,
                          background: Colors.white,
                          foreground: _Web.slate700,
                          border: _line,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'أدوات إضافية',
                          onSelected: (label) => widget.actions[label]?.call(),
                          itemBuilder: (_) => [
                            for (final label in [
                              'خصم نسبة',
                              'تعديل الصافي',
                              'سجل الفواتير',
                              'سند قبض',
                              'كشف حساب العميل',
                              'إضافة عميل',
                              'إعادة طباعة آخر فاتورة',
                            ])
                              if (widget.actions[label] != null)
                                PopupMenuItem(
                                  value: label,
                                  child: Text(label, style: _Web.text(12)),
                                ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: _Web.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final button in [
                  _webButton(
                    'حفظ',
                    onTap: ready ? widget.actions['حفظ'] : null,
                    shortcut: 'F3',
                    height: 45,
                    fontSize: 11.2,
                    twoLines: true,
                    background: _slate,
                    disabledBackground: _line,
                    disabledForeground: _Web.slate400,
                  ),
                  _webButton(
                    'حفظ وطباعة',
                    onTap: ready ? widget.actions['حفظ وطباعة'] : null,
                    shortcut: 'F6',
                    height: 45,
                    fontSize: 11.2,
                    twoLines: true,
                    background: _Web.emerald600,
                    disabledBackground: _line,
                    disabledForeground: _Web.slate400,
                  ),
                  _webButton(
                    'فاتورة جديدة',
                    onTap: hasLines || widget.editingInvoiceId != null
                        ? (widget.actions['فاتورة جديدة'] ?? widget.onClear)
                        : null,
                    shortcut: 'F4',
                    height: 45,
                    fontSize: 11.2,
                    twoLines: true,
                    background: _Web.slate50,
                    foreground: _Web.slate600,
                    border: _line,
                  ),
                  _webButton(
                    'PDF',
                    onTap: widget.actions['PDF'],
                    icon: '📄',
                    sub: 'فاتورة',
                    height: 45,
                    fontSize: 11.2,
                    background: _Web.red50,
                    foreground: _Web.red700,
                    border: _Web.red200,
                  ),
                  _webButton(
                    'نسخ',
                    onTap: hasLines ? widget.actions['نسخ'] : null,
                    icon: '📋',
                    sub: 'فاتورة جديدة',
                    height: 45,
                    fontSize: 11.2,
                    background: _Web.violet50,
                    foreground: _Web.violet700,
                    border: _Web.violet200,
                  ),
                  _webButton(
                    'واتساب',
                    onTap: widget.actions['واتساب'],
                    icon: '🟢',
                    sub: 'حفظ وإرسال',
                    height: 45,
                    fontSize: 11.2,
                    background: _Web.green50,
                    foreground: _Web.green700,
                    border: _Web.green200,
                  ),
                ]) ...[gap, Expanded(flex: 218, child: button)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One web footer box: label row on top, then the value or its field.
  Widget _webAmount(
    String label, {
    required Widget child,
    Color labelColor = _Web.slate500,
    Color background = _Web.slate50,
    Color border = _line,
    Widget? trailing,
  }) => Expanded(
    child: Container(
      margin: const EdgeInsetsDirectional.only(start: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border, width: .8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Web.text(
                    9,
                    weight: FontWeight.w900,
                    color: labelColor,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    ),
  );

  Widget _webValue(String value, Color color, {double height = 40}) =>
      Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value,
          style: _Web.text(
            16,
            weight: FontWeight.w900,
            color: color,
            mono: true,
          ),
        ),
      );

  Widget _referencePayment() {
    final paidEntered = _paid.text.trim().isNotEmpty;
    final change = _paidAmount - widget.total;
    final owing = paidEntered && change < -.005;
    return Container(
      key: const Key('pos-payment-footer'),
      height: 151,
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line, width: .8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 575,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _Web.slate50,
                border: Border.all(color: _line, width: .8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الزبون', style: _Web.text(10, weight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  CustomerPicker(
                    customers: widget.customers,
                    value: widget.customerId,
                    placeholder: 'إضافة زبون للفاتورة',
                    onRefresh: widget.onRefreshCustomers,
                    onChanged: widget.onCustomer,
                    appearance: (name, chosen) => Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _Web.blue200, width: .8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('👤', style: _Web.text(12, color: _Web.blue700)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Web.text(
                                12,
                                weight: FontWeight.w900,
                                color: _Web.blue700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onRecipientName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'اسم المستلم على الفاتورة',
                      style: _Web.text(
                        9,
                        weight: FontWeight.w900,
                        color: _Web.slate600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 36,
                      child: TextField(
                        key: const Key('pos-recipient-name'),
                        controller: _recipient,
                        style: _Web.text(14, color: _Web.slate900),
                        decoration: _Web.field(hint: 'زبون عام', radius: 8),
                        onChanged: widget.onRecipientName,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 429,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _Web.slate50,
                border: Border.all(color: _line, width: .8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طريقة الدفع',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Web.text(10, weight: FontWeight.w900),
                            ),
                            Text(
                              'اختر طريقة الدفع',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Web.text(8, color: _Web.slate400),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _Web.emerald50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'بيع',
                          style: _Web.text(
                            8,
                            weight: FontWeight.w900,
                            color: _Web.emerald700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (final method in const [
                        ('cash', '💵', 'نقدي'),
                        ('card', '💳', 'بطاقة'),
                        ('bank_transfer', '🏦', 'تحويل'),
                        ('cheque', '🧾', 'شيك'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: _webButton(
                              method.$3,
                              onTap: () => widget.onPayment(method.$1),
                              icon: method.$2,
                              height: 38,
                              fontSize: 11.2,
                              background: widget.paymentMethod == method.$1
                                  ? _blue
                                  : Colors.white,
                              foreground: widget.paymentMethod == method.$1
                                  ? Colors.white
                                  : _Web.slate700,
                              border: widget.paymentMethod == method.$1
                                  ? _blue
                                  : _line,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 876,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _webAmount(
                  'الإجمالي',
                  child: _webValue(_money(widget.subtotal), _slate),
                ),
                _webAmount(
                  'الخصم',
                  trailing: Text(
                    'مبلغ',
                    style: _Web.text(9, weight: FontWeight.w900, color: _blue),
                  ),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _discount,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: _Web.text(
                        14,
                        weight: FontWeight.w900,
                        color: _Web.blue700,
                      ),
                      decoration: _Web.field(
                        hint: '0',
                        radius: 8,
                        border: _discountError == null ? _line : _Web.rose500,
                      ),
                      onChanged: (value) {
                        final amount = value.trim().isEmpty
                            ? 0.0
                            : SaleData.number(value);
                        final valid =
                            amount != null &&
                            amount >= 0 &&
                            amount <= widget.subtotal;
                        _refreshDesktop(
                          () => _discountError = valid
                              ? null
                              : 'أدخل خصماً صالحاً',
                        );
                        widget.onDiscountValidity?.call(valid);
                        if (valid) widget.onDiscount(amount);
                      },
                    ),
                  ),
                ),
                _webAmount(
                  'التوصيل',
                  child: InkWell(
                    onTap: widget.actions['التوصيل'],
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _line, width: .8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.deliveryFee == 0
                            ? '0'
                            : _money(widget.deliveryFee),
                        style: _Web.text(
                          14,
                          weight: FontWeight.w900,
                          color: _Web.blue700,
                        ),
                      ),
                    ),
                  ),
                ),
                _webAmount(
                  'الصافي للدفع',
                  labelColor: _Web.amber700,
                  background: _Web.amber50,
                  border: _Web.amber200,
                  child: _webValue(
                    _money(widget.total),
                    _Web.amber700,
                    height: 52,
                  ),
                ),
                _webAmount(
                  'المدفوع',
                  labelColor: _Web.blue800,
                  background: _Web.blue50,
                  border: _Web.blue200,
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      key: const Key('pos-paid-input'),
                      controller: _paid,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: _Web.text(
                        14,
                        weight: FontWeight.w900,
                        color: _Web.blue800,
                      ),
                      decoration: _Web.field(
                        hint: '0',
                        radius: 8,
                        border: _Web.blue200,
                        borderWidth: 1.6,
                      ),
                      onChanged: (_) {
                        _refreshDesktop(() {});
                        _notifyTender();
                      },
                    ),
                  ),
                ),
                _webAmount(
                  owing ? 'المتبقي' : 'الباقي',
                  labelColor: owing ? _Web.rose600 : _Web.emerald700,
                  background: owing ? _Web.rose50 : _Web.emerald50,
                  border: owing ? _Web.rose200 : _Web.emerald200,
                  child: _webValue(
                    _money(change.abs()),
                    owing ? _Web.rose600 : _Web.emerald700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _webChip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: Material(
      color: selected ? _blue : _Web.slate50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? _Web.blue500 : _line, width: .8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 33,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            style: _Web.text(
              10,
              weight: FontWeight.w900,
              color: selected ? Colors.white : _Web.slate700,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _referenceCatalog() {
    final hint = _Web.text(9, weight: FontWeight.w600, color: _Web.slate500);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line, width: .8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: _Web.slate50,
              border: Border(bottom: BorderSide(color: _line, width: .8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الأصناف',
                          style: _Web.text(14, weight: FontWeight.w900),
                        ),
                        Text(
                          '${widget.products.length} صنف',
                          style: _Web.text(9, color: _Web.slate400),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _webButton(
                      'تحديث',
                      onTap: widget.actions['تحديث الأصناف'],
                      icon: '↻',
                      height: 29,
                      fontSize: 10,
                      background: Colors.white,
                      foreground: _Web.slate600,
                      border: _line,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      key: const Key('pos-catalog-search'),
                      controller: _catalogSearch,
                      focusNode: widget.catalogFocus,
                      onChanged: _onCatalogSearch,
                      style: _Web.text(14),
                      decoration: _Web.field(
                        hint: 'اسم الصنف، أي كلمات منه، رقمه أو باركوده…',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'سعر البيع — اختياري',
                  style: _Web.text(10, color: _Web.slate600),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 36,
                  child: TextField(
                    key: const Key('pos-price-filter'),
                    controller: _priceFilter,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _onPriceFilter,
                    style: _Web.text(14),
                    decoration: _Web.field(hint: '75.00'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يطابق سعر البيع في الفرع الحالي، ويمكن دمجه مع بحث الصنف.',
                  style: _Web.text(
                    9,
                    weight: FontWeight.w400,
                    color: _Web.slate500,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'الكلمات بأي ترتيب · يدعم اختلافات الألف والياء والتشكيل',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hint,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'F2 بحث · ↓ اختيار · Enter إضافة · Esc مسح',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hint,
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
  }

  /// Web: «الكل», one chip per category, and «عروض» when a product has an offer.
  Widget _referenceFilters() {
    final hasOffers = widget.products.any(_PosWorkspaceState._hasOffer);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line, width: .8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _webChip(
              'الكل',
              !_offersOnly && widget.selectedCategoryId == null,
              () {
                _showOffers(false);
                widget.onCategory(null);
              },
            ),
            for (final category in widget.categories)
              if (SaleData.id(category['id']) != null)
                _webChip(
                  '${category['name'] ?? ''}',
                  !_offersOnly &&
                      widget.selectedCategoryId == SaleData.id(category['id']),
                  () {
                    if (_offersOnly) _refreshDesktop(() => _offersOnly = false);
                    widget.onCategory(SaleData.id(category['id']));
                  },
                ),
            if (hasOffers || _offersOnly)
              _webChip('عروض', _offersOnly, () => _showOffers(true)),
          ],
        ),
      ),
    );
  }

  static const _rowExtent = 49.0;

  /// Web-style product table: one product per row, ↑/↓ move, Enter adds.
  Widget _referenceProductTable() {
    final products = _deskProducts;
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final extent = _rowExtent * scale;
    final headerStyle = _Web.text(11, color: Colors.white);
    return Container(
      color: _Web.slate100,
      padding: const EdgeInsetsDirectional.fromSTEB(9, 8, 9, 0),
      child: Column(
        children: [
          Container(
            key: const Key('pos-product-table-header'),
            height: 33,
            color: _Web.slate800,
            child: Row(
              children: [
                Expanded(
                  flex: 176,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      'الصنف / رقم الصنف / الباركود',
                      style: headerStyle,
                    ),
                  ),
                ),
                SizedBox(
                  width: 67,
                  child: Text(
                    'سعر البيع',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    'المتوفر',
                    textAlign: TextAlign.center,
                    style: headerStyle,
                  ),
                ),
                const Spacer(flex: 276),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: products.isEmpty
                  ? Center(
                      child: Text(
                        _offersOnly ? 'لا توجد عروض' : 'لا توجد منتجات مطابقة',
                        style: _Web.text(12, color: _Web.slate500),
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
          ),
        ],
      ),
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
    final muted = _Web.text(9, weight: FontWeight.w400, color: _Web.slate500);
    final mutedMono = _Web.text(
      9,
      weight: FontWeight.w400,
      color: _Web.slate500,
      mono: true,
    );
    return Material(
      key: ValueKey('pos-product-$index'),
      color: active
          ? _Web.indigo50
          : index.isOdd
          ? _Web.slate50.withValues(alpha: .7)
          : Colors.white,
      child: InkWell(
        canRequestFocus: false,
        hoverColor: _Web.indigo50,
        onTap: widget.busy || widget.repricing
            ? null
            : () => _selectProduct(Map<String, dynamic>.from(product)),
        child: Container(
          decoration: BoxDecoration(
            border: active
                ? Border.all(color: _Web.indigo500, width: 2)
                : const Border(bottom: BorderSide(color: _Web.slate100)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 176,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
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
                              style: _Web.text(
                                11,
                                weight: FontWeight.w900,
                                color: soldOut ? _Web.slate500 : _Web.slate800,
                              ),
                            ),
                          ),
                          if (soldOut) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _Web.rose100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'نافد',
                                style: _Web.text(
                                  9,
                                  weight: FontWeight.w900,
                                  color: _Web.rose700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'رقم: ', style: muted),
                            TextSpan(
                              text:
                                  '${product['product_number'] ?? product['id'] ?? '—'}',
                              style: mutedMono,
                            ),
                            TextSpan(text: '    باركود: ', style: muted),
                            TextSpan(
                              text: barcode.isEmpty ? '—' : barcode,
                              style: mutedMono,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (offerQuantity > 0 && offerPrice != null)
                        Text(
                          'عرض ${_quantity(offerQuantity)} بـ ${_money(offerPrice)}',
                          maxLines: 1,
                          style: _Web.text(
                            9,
                            weight: FontWeight.w900,
                            color: _Web.emerald700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 67,
                child: Text(
                  price == null ? 'غير مسعّر' : _money(price),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: _Web.text(
                    11,
                    weight: FontWeight.w900,
                    color: price == null ? _Web.rose600 : _Web.blue700,
                    mono: price != null,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: soldOut ? _Web.rose100 : _Web.slate50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stockLabel(product),
                      textDirection: TextDirection.ltr,
                      style: _Web.text(
                        9,
                        color: soldOut ? _Web.rose700 : _Web.emerald700,
                        mono: true,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 276),
            ],
          ),
        ),
      ),
    );
  }

  /// Invoice columns of the web table: # · رقم المنتج · الصنف · الكمية · السعر · المتبقي · الإجمالي · actions.
  Widget _invoiceColumns(List<Widget> cells) => Row(
    children: [
      SizedBox(width: 48, child: cells[0]),
      Expanded(flex: 89, child: cells[1]),
      Expanded(flex: 483, child: cells[2]),
      Expanded(flex: 138, child: cells[3]),
      Expanded(flex: 162, child: cells[4]),
      Expanded(flex: 91, child: cells[5]),
      Expanded(flex: 226, child: cells[6]),
      SizedBox(width: 48, child: cells[7]),
    ],
  );

  PosCellLook _cellLook(Color fill, Color color) => PosCellLook(
    style: _Web.text(14, weight: FontWeight.w900, color: color),
    decoration: _Web.field(
      fill: fill,
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    ),
  );

  Widget _webBadge(
    String text, {
    required Color background,
    required Color border,
    required Color color,
    double minWidth = 28,
  }) => Container(
    constraints: BoxConstraints(minWidth: minWidth, minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border, width: .8),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: _Web.text(11, weight: FontWeight.w900, color: color, mono: true),
    ),
  );

  Widget _webInvoice() {
    final quantity = widget.cart.fold<double>(
      0,
      (sum, item) => sum + (SaleData.number(item['quantity']) ?? 0),
    );
    final headerStyle = _Web.text(12, color: _Web.slate600);
    // Web: each product name gets its own hue, spread over the palette.
    final hues = <String, double>{};
    final names = <String>[];
    for (final item in widget.cart) {
      final key = ProductCatalog.normalizeSearch('${item['name'] ?? ''}');
      if (!names.contains(key)) names.add(key);
    }
    for (var i = 0; i < names.length; i++) {
      hues[names[i]] = 70 + (i * 210) / math.max(1, names.length);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line, width: .8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: _Web.slate50,
              border: Border(bottom: BorderSide(color: _Web.slate100)),
            ),
            child: Row(
              children: [
                SizedBox(
                  height: 44,
                  child: _webButton(
                    'إضافة',
                    onTap: () =>
                        widget.onSubmitBarcode(widget.barcodeController.text),
                    height: 44,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      key: const Key('pos-barcode-input'),
                      controller: widget.barcodeController,
                      focusNode: widget.barcodeFocus,
                      onChanged: widget.onBarcode,
                      onSubmitted: widget.onSubmitBarcode,
                      style: _Web.text(
                        14,
                        weight: FontWeight.w900,
                        color: _slate,
                      ),
                      decoration: _Web.field(
                        hint: 'امسح الباركود · للكمية اكتب 3* ثم امسح',
                        border: _Web.blue200,
                        borderWidth: 1.6,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: _Web.blue200, width: .8),
                  ),
                  child: InkWell(
                    onTap: widget.onScan,
                    borderRadius: BorderRadius.circular(12),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Tooltip(
                        message: 'مسح بالكاميرا',
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 20,
                          color: _blue,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _Web.slate100)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'تجميع الأصناف المتشابهة',
                              style: _Web.text(12, weight: FontWeight.w900),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _Web.slate50,
                                border: Border.all(color: _line, width: .8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'الكمية: ${_quantity(quantity)}',
                                style: _Web.text(
                                  10,
                                  weight: FontWeight.w900,
                                  color: _blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'كل إضافة تظهر كسطر مستقل',
                          style: _Web.text(10, color: _Web.slate400),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: FittedBox(
                    child: Switch(
                      value: widget.mergeSimilar,
                      onChanged: widget.onMergeSimilar,
                      activeThumbColor: Colors.white,
                      activeTrackColor: _blue,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: _Web.slate300,
                      trackOutlineColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 48,
            decoration: const BoxDecoration(
              color: _Web.slate100,
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: _invoiceColumns([
              Text('#', textAlign: TextAlign.center, style: headerStyle),
              Text(
                'رقم المنتج',
                textAlign: TextAlign.center,
                style: headerStyle,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Text('الصنف', style: headerStyle),
              ),
              Text('الكمية', textAlign: TextAlign.center, style: headerStyle),
              Text('السعر', textAlign: TextAlign.center, style: headerStyle),
              Text('المتبقي', textAlign: TextAlign.center, style: headerStyle),
              Text('الإجمالي', textAlign: TextAlign.center, style: headerStyle),
              const SizedBox(),
            ]),
          ),
          Expanded(
            child: widget.cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 40,
                          color: _Web.slate400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الفاتورة فارغة',
                          style: _Web.text(
                            14,
                            weight: FontWeight.w900,
                            color: _Web.slate400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'امسح الباركود أو افتح قائمة الأصناف F10',
                          style: _Web.text(11, color: _Web.slate300),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    key: const Key('pos-invoice-lines'),
                    controller: _invoiceScroll,
                    children: [
                      for (var index = 0; index < widget.cart.length; index++)
                        _webInvoiceLine(index, hues),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _webInvoiceLine(int index, Map<String, double> hues) {
    final item = widget.cart[index];
    final hue =
        hues[ProductCatalog.normalizeSearch('${item['name'] ?? ''}')] ?? 70;
    final tinted = !widget.mergeSimilar;
    final occurrence = widget.cart
        .take(index + 1)
        .where(
          (line) =>
              SaleData.id(line['product_id'] ?? line['id']) ==
              SaleData.id(item['product_id'] ?? item['id']),
        )
        .length;
    final unitPrice =
        (SaleData.number(item['price']) ?? 0) -
        (SaleData.number(item['discount']) ?? 0);
    final stock = StockPreview.quantities(
      item,
      widget.cart,
      project: widget.editingInvoiceId == null,
    );
    final left = stock.total ?? stock.local;
    final short = left != null && left < 0;
    final editable = widget.onLineValue != null;
    Widget box(double width, Widget child) => Center(
      child: SizedBox(width: width, height: 36, child: child),
    );
    return Container(
      key: _lineKey(index),
      height: 76,
      decoration: BoxDecoration(
        color: tinted ? _Web.hsl(hue, .72, .96) : Colors.white,
        border: const Border(
          bottom: BorderSide(color: _Web.slate300, width: .8),
        ),
      ),
      child: _invoiceColumns([
        Center(
          child: _webBadge(
            '${index + 1}',
            background: _Web.indigo50,
            border: _Web.indigo100,
            color: _Web.indigo700,
          ),
        ),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _webBadge(
              '${item['product_number'] ?? item['product_id'] ?? '—'}',
              background: _Web.slate50,
              border: _line,
              color: _Web.slate600,
            ),
          ),
        ),
        Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: tinted
              ? BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: _Web.hsl(hue, .62, .43), width: 3),
                  ),
                )
              : null,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  "${item['name'] ?? 'منتج'}${item['gift'] == true ? ' — هدية' : ''}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _Web.text(12, weight: FontWeight.w900),
                ),
              ),
              // «الأسعار» and the repeat badge shrink before they could push the row out.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onEditLine != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          key: ValueKey('pos-edit-line-$index'),
                          onTap: () => widget.onEditLine!(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Text(
                              'الأسعار',
                              style: _Web.text(12, color: _Web.emerald700),
                            ),
                          ),
                        ),
                      ],
                      if (tinted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: _Web.hsl(hue, .70, .89),
                            border: Border.all(color: _Web.hsl(hue, .60, .73)),
                            borderRadius: BorderRadius.circular(6.4),
                          ),
                          child: Text(
                            '$occurrence',
                            style: _Web.text(
                              12,
                              weight: FontWeight.w900,
                              color: _Web.hsl(hue, .70, .24),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        editable
            ? Center(
                child: SizedBox(
                  width: 66,
                  height: 38,
                  child: _numberCell(
                    index,
                    0,
                    SaleData.number(item['quantity']) ?? 1,
                    look: _cellLook(Colors.white, _slate),
                  ),
                ),
              )
            : Center(
                child: Text(
                  _quantity(item['quantity']),
                  style: _Web.text(14, weight: FontWeight.w900),
                ),
              ),
        editable
            ? box(
                80,
                _numberCell(
                  index,
                  1,
                  unitPrice,
                  look: _cellLook(_Web.slate50, _Web.slate800),
                ),
              )
            : Center(
                child: Text(
                  _money(unitPrice),
                  style: _Web.text(14, weight: FontWeight.w900),
                ),
              ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: short ? _Web.rose100 : _Web.emerald50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _stockLabel(item, project: true),
              textDirection: TextDirection.ltr,
              style: _Web.text(
                11,
                color: short ? _Web.rose700 : _Web.emerald700,
                mono: true,
              ),
            ),
          ),
        ),
        editable
            ? box(
                96,
                _numberCell(
                  index,
                  2,
                  SaleData.lineTotal(item),
                  look: _cellLook(_Web.slate50, _Web.blue700),
                ),
              )
            : Center(
                child: Text(
                  _money(SaleData.lineTotal(item)),
                  style: _Web.text(
                    14,
                    weight: FontWeight.w900,
                    color: _Web.blue700,
                  ),
                ),
              ),
        Center(
          child: InkWell(
            onTap: () => widget.onRemove(index),
            borderRadius: BorderRadius.circular(8),
            child: Tooltip(
              message: 'حذف الصنف',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '×',
                  style: _Web.text(
                    18,
                    weight: FontWeight.w900,
                    color: _Web.rose500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _matchedDesktop() {
    final ready =
        widget.cart.isNotEmpty && _discountError == null && _tenderValid;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: _Web.font),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: _Web.font),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: _Web.font),
        child: AbsorbPointer(
          absorbing: widget.busy || widget.repricing,
          child: ColoredBox(
            color: _Web.slate100,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _matchedToolbar(ready),
                  const SizedBox(height: 8),
                  if (widget.busy || widget.repricing)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 609, child: _referenceCatalog()),
                        const SizedBox(width: 8),
                        Expanded(flex: 1287, child: _desktopInvoice()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _referencePayment(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
