import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/services/barcode_service.dart';

void main() {
  final product = {
    'id': 1,
    'barcode': '00123456',
    'barcodes': [
      {'barcode': ' ABC-123 '},
      '99887766',
      12345678,
      null,
      {'barcode': null},
    ],
  };
  final categories = [
    {
      'products': [product],
    },
  ];

  test('matches primary and mixed additional barcode data', () {
    for (final code in ['00123456', ' abc-123\r\n', '99887766', '12345678']) {
      expect(BarcodeService.findProduct(categories, code)?['id'], 1);
    }
  });

  test('preserves leading zeros and requires the whole barcode', () {
    for (final code in ['', '123456', '001234', 'unknown']) {
      expect(BarcodeService.findProduct(categories, code), isNull);
    }
  });

  test('handles products without additional barcodes', () {
    expect(BarcodeService.codes({'barcode': '0123'}), ['0123']);
    expect(BarcodeService.codes({}), isEmpty);
  });
}
