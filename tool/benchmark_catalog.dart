import 'dart:io';

import 'package:waslapos_app/models/product_catalog.dart';
import 'package:waslapos_app/services/barcode_service.dart';

void main() {
  const count = 20000;
  const lookups = 100;
  final categories = [
    {
      'id': 1,
      'products': List.generate(
        count,
        (i) => {'id': i, 'name': 'Product $i', 'barcode': 'CODE$i'},
      ),
    },
  ];
  final build = Stopwatch()..start();
  final catalog = ProductCatalog(categories);
  build.stop();
  final linear = Stopwatch()..start();
  for (var i = 0; i < lookups; i++) {
    if (BarcodeService.findProduct(categories, 'CODE19999')?['id'] != 19999) {
      throw StateError('Missing product');
    }
  }
  linear.stop();
  final indexed = Stopwatch()..start();
  for (var i = 0; i < lookups; i++) {
    if (catalog.findBarcode('CODE19999')?['id'] != 19999) {
      throw StateError('Missing product');
    }
  }
  indexed.stop();
  stdout.writeln('Products: $count; lookups: $lookups');
  stdout.writeln('Index construction: ${build.elapsedMicroseconds / 1000} ms');
  stdout.writeln('Linear lookups: ${linear.elapsedMicroseconds / 1000} ms');
  stdout.writeln('Indexed lookups: ${indexed.elapsedMicroseconds / 1000} ms');
}
