part of 'pos_workspace.dart';

/// The web POS «تحليل التكلفة والربح» window: a blue header, one row per line with its price,
/// cost, total cost and profit, and the cost and expected profit (after the invoice discount) below.
Future<void> showCartCostDialog(
  BuildContext context,
  List<Map<String, dynamic>> cart,
  double total,
) => showDialog<void>(
  context: context,
  barrierColor: const Color(0xBF020617),
  builder: (_) => _CostDialog(cart: cart, total: total),
);

class _CostDialog extends StatelessWidget {
  const _CostDialog({required this.cart, required this.total});
  final List<Map<String, dynamic>> cart;
  final double total;

  static String _money(double value) => value.toStringAsFixed(2);
  static String _quantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  static double _sold(Map line) {
    try {
      return SaleData.lineTotal(line);
    } on FormatException {
      return (SaleData.number(line['price']) ?? 0) *
          (SaleData.number(line['quantity']) ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing =
        cart.isEmpty ||
        cart.any((line) => SaleData.number(line['cost_price']) == null);
    final cost = cart.fold<double>(
      0,
      (sum, line) =>
          sum +
          (SaleData.number(line['cost_price']) ?? 0) *
              (SaleData.number(line['quantity']) ?? 0),
    );
    final profit = total - cost;
    final head = _Web.text(12, weight: FontWeight.w900, color: _Web.slate700);
    final number = _Web.text(12, mono: true);

    Widget cell(Widget child, {int flex = 2, bool end = false}) => Expanded(
      flex: flex,
      child: Align(
        alignment: end ? AlignmentDirectional.centerStart : Alignment.center,
        child: child,
      ),
    );
    Widget amount(String text, {Color color = _Web.slate800}) => Text(
      text,
      textDirection: TextDirection.ltr,
      style: number.copyWith(color: color, fontWeight: FontWeight.w900),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        key: const Key('pos-cost-dialog'),
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1008),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: _Web.blue700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'تحليل التكلفة والربح',
                        style: _Web.text(
                          14,
                          weight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('pos-cost-dialog-x'),
                      tooltip: 'إغلاق',
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: _Web.slate100,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            cell(
                              Text('الصنف', style: head),
                              flex: 5,
                              end: true,
                            ),
                            cell(Text('الكمية', style: head)),
                            cell(Text('السعر', style: head)),
                            cell(Text('التكلفة', style: head)),
                            cell(Text('إجمالي التكلفة', style: head)),
                            cell(Text('الربح', style: head)),
                          ],
                        ),
                      ),
                      for (final (index, line) in cart.indexed)
                        _row(line, index, cell, amount),
                      if (missing)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'لم يرسل الخادم تكلفة جميع الأصناف؛ لا يمكن حساب الربح بدقة.',
                            style: _Web.text(12, color: _Web.rose700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: _Web.slate50,
                  border: Border(top: BorderSide(color: _Web.slate200)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _total(
                          'التكلفة:',
                          missing ? '—' : _money(cost),
                          _Web.rose600,
                          amount,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _total(
                          'الربح المتوقع:',
                          missing ? '—' : _money(profit),
                          profit < 0 ? _Web.rose600 : _Web.emerald600,
                          amount,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: SizedBox(
                          height: 40,
                          child: FilledButton(
                            key: const Key('pos-cost-dialog-close'),
                            autofocus: true,
                            style: FilledButton.styleFrom(
                              backgroundColor: _Web.slate800,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'إغلاق',
                              style: _Web.text(
                                13,
                                weight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    Map<String, dynamic> line,
    int index,
    Widget Function(Widget, {int flex, bool end}) cell,
    Widget Function(String, {Color color}) amount,
  ) {
    final quantity = SaleData.number(line['quantity']) ?? 0;
    final unitCost = SaleData.number(line['cost_price']);
    final lineCost = unitCost == null ? null : unitCost * quantity;
    final profit = lineCost == null ? null : _sold(line) - lineCost;
    final gift = line['gift'] == true;
    return Container(
      key: Key('pos-cost-line-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Web.slate100)),
      ),
      child: Row(
        children: [
          cell(
            Text(
              '${line['name'] ?? ''}${gift ? ' — هدية' : ''}',
              style: _Web.text(12, weight: FontWeight.w900),
            ),
            flex: 5,
            end: true,
          ),
          cell(amount(_quantity(quantity))),
          cell(
            amount(gift ? '0.00' : _money(SaleData.number(line['price']) ?? 0)),
          ),
          cell(amount(unitCost == null ? '—' : _money(unitCost))),
          cell(
            amount(
              lineCost == null ? '—' : _money(lineCost),
              color: _Web.rose600,
            ),
          ),
          cell(
            amount(
              profit == null ? '—' : _money(profit),
              color: (profit ?? 0) < 0 ? _Web.rose600 : _Web.emerald600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(
    String label,
    String value,
    Color color,
    Widget Function(String, {Color color}) amount,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: _Web.text(12, weight: FontWeight.w900)),
      const SizedBox(width: 4),
      amount(value, color: color),
    ],
  );
}
