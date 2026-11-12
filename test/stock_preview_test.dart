import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/models/stock_preview.dart';

void main() {
  const product = {'id': 1, 'stock_quantity': 2, 'shared_stock_quantity': 12};
  test(
    'selection shows local stock and total without deducting cart quantities',
    () {
      final values = StockPreview.quantities(product, [
        {'product_id': 1, 'quantity': 3},
      ]);
      expect(values, (local: 2.0, total: 12.0));
    },
  );
  test('shared projection exhausts local stock before borrowing', () {
    final values = StockPreview.quantities(product, [
      {'product_id': 1, 'quantity': 3},
    ], project: true);
    expect(values, (local: 0.0, total: 9.0));
  });
  test('duplicate and gift rows share the same remaining quantities', () {
    final values = StockPreview.quantities(product, [
      {'product_id': 1, 'quantity': 1},
      {'product_id': 1, 'quantity': 1, 'gift': true},
      {'product_id': 2, 'quantity': 9},
    ], project: true);
    expect(values, (local: 0.0, total: 10.0));
  });
  test('disabled sharing omits total and keeps negative local projections', () {
    final values = StockPreview.quantities(
      {'id': 1, 'stock_quantity': 2},
      [
        {'product_id': 1, 'quantity': 3},
      ],
      project: true,
    );
    expect(values, (local: -1.0, total: null));
  });
}
