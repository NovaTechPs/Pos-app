import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/models/product_catalog.dart';

void main() {
  test(
    'complete barcode detection never consumes a prefix of a longer code',
    () {
      final catalog = ProductCatalog([
        {
          'products': [
            {'id': 1, 'barcode': '001'},
            {'id': 2, 'barcode': '00123'},
            {
              'id': 3,
              'barcode': 'ABC',
              'barcodes': [
                {'barcode': 'ABC456'},
              ],
            },
          ],
        },
      ]);
      expect(catalog.isCompleteBarcode('001'), false);
      expect(catalog.isCompleteBarcode('0012'), false);
      expect(catalog.isCompleteBarcode('00123'), true);
      expect(catalog.isCompleteBarcode('abc'), false);
      expect(catalog.isCompleteBarcode(' abc456 '), true);
    },
  );
  test('Arabic catalog search matches word order spelling marks and product number', () {
    final catalog = ProductCatalog([
      {
        'id': 1,
        'products': [
          {
            'id': 12,
            'product_number': 'P-250',
            'name': 'قَهْوَة أحمد عربي',
            'barcode': '0012',
          },
        ],
      },
    ]);
    expect(catalog.search('عربى احمد', null).single['id'], 12);
    expect(catalog.search('P-250', null).single['id'], 12);
    expect(catalog.search('قهوة', null).single['id'], 12);
  });
  final categories = [
    {
      'id': 1,
      'products': [
        {
          'id': 1,
          'name': 'Coffee',
          'barcode': '001',
          'barcodes': [
            {'barcode': 'ALIAS'},
          ],
        },
        {'id': 2, 'name': 'Tea', 'barcode': '002'},
      ],
    },
    {
      'id': 2,
      'products': [
        {'id': 3, 'name': 'Milk', 'barcode': '003'},
      ],
    },
  ];
  test('indexed barcode preserves aliases, case, zeros and misses', () {
    final catalog = ProductCatalog(categories);
    expect(catalog.findBarcode(' alias ')?['id'], 1);
    expect(catalog.findBarcode('001')?['id'], 1);
    expect(catalog.findBarcode('1'), isNull);
    expect(catalog.findBarcode(''), isNull);
    final copy = catalog.findBarcode('001')!;
    copy['name'] = 'changed';
    expect(catalog.findBarcode('001')?['name'], 'Coffee');
  });
  test(
    'search caches unchanged views and honors categories and barcode fragments',
    () {
      final catalog = ProductCatalog(categories);
      final first = catalog.search('', 1);
      expect(first.length, 2);
      expect(identical(first, catalog.search('', 1)), isTrue);
      expect(catalog.search('', 2).single['id'], 3);
      expect(catalog.search('MIL', 1).single['id'], 3);
      expect(catalog.search('lia', null).single['id'], 1);
      expect(catalog.search('nothing', null), isEmpty);
    },
  );
  test(
    'new catalog replaces stale prices and duplicate codes keep first match',
    () {
      final catalog = ProductCatalog([
        {
          'id': 1,
          'products': [
            {'id': 1, 'name': 'A', 'barcode': 'x', 'retail_price': 12},
            {'id': 2, 'name': 'B', 'barcode': 'x', 'retail_price': 25},
          ],
        },
      ]);
      expect(catalog.findBarcode('x')?['id'], 1);
      expect(catalog.findBarcode('x')?['retail_price'], 12);
    },
  );
}
