part of 'pos_workspace.dart';

/// Sold lines priced under their cost, as the web POS lists them before saving: gift lines and
/// lines without a quantity are left out.
List<Map> belowCostLines(List<dynamic> cart) => cart
    .whereType<Map>()
    .where(
      (line) =>
          line['gift'] != true &&
          (SaleData.number(line['quantity']) ?? 0) > 0 &&
          (SaleData.number(line['price']) ?? 0) <
              (SaleData.number(line['cost_price']) ?? 0),
    )
    .toList();

/// The web POS «⚠ تأكيد البيع تحت التكلفة» window: true continues and saves the sale.
Future<bool> showBelowCostDialog(
  BuildContext context, {
  required List<Map> lines,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xBF020617),
      builder: (_) => _BelowCostDialog(lines: lines),
    ) ==
    true;

class _BelowCostDialog extends StatelessWidget {
  const _BelowCostDialog({required this.lines});
  final List<Map> lines;

  static const _amber500 = Color(0xFFF59E0B);
  static const _amber100 = Color(0xFFFEF3C7);

  String _money(Object? value) =>
      (SaleData.number(value) ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Dialog(
      key: const Key('pos-below-cost-dialog'),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _amber500,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠ تأكيد البيع تحت التكلفة',
                    style: _Web.text(
                      14,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'يوجد صنف واحد أو أكثر بسعر بيع أقل من التكلفة.',
                    style: _Web.text(10, color: _amber100),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 224),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: lines.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final line = lines[index];
                  return Container(
                    key: Key('pos-below-cost-line-$index'),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _Web.amber50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line['name'] ?? ''}',
                            style: _Web.text(12, weight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${_money(line['price'])} / ${_money(line['cost_price'])}',
                          textDirection: TextDirection.ltr,
                          style: _Web.text(
                            12,
                            weight: FontWeight.w900,
                            color: _Web.rose700,
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        key: const Key('pos-below-cost-confirm'),
                        autofocus: true,
                        style: FilledButton.styleFrom(
                          backgroundColor: _amber500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          'متابعة وحفظ',
                          style: _Web.text(
                            12,
                            weight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        key: const Key('pos-below-cost-cancel'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _Web.slate100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          'إلغاء',
                          style: _Web.text(
                            12,
                            weight: FontWeight.w900,
                            color: _Web.slate700,
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
