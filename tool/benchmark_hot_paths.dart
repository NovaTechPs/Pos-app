import 'dart:convert';
import 'dart:io';

import 'package:waslapos_app/models/product_catalog.dart';
import 'package:waslapos_app/models/sale_data.dart';

double measure(void Function() work) {
  work();
  final runs = <double>[];
  for (var i = 0; i < 5; i++) {
    final timer = Stopwatch()..start();
    work();
    runs.add(timer.elapsedMicroseconds / 1000);
  }
  runs.sort();
  return runs[2];
}

void main(List<String> args) {
  final categories = [
    {
      'id': 1,
      'products': List.generate(
        20000,
        (i) => {
          'id': i,
          'name': 'قَهْوَة أحمد صنف عربي $i',
          'barcode': 'CODE$i',
          'product_number': 'P-$i',
        },
      ),
    },
  ];
  var checksum = 0.0;
  final indexMs = measure(() {
    final catalog = ProductCatalog(categories);
    if (catalog.findBarcode('CODE19999')?['id'] != 19999) {
      throw StateError('index');
    }
  });
  final catalog = ProductCatalog(categories);
  final searchMs = measure(() {
    for (var i = 0; i < 100; i++) {
      checksum += catalog.search('عربى احمد ${19000 + i}', null).length;
    }
  });
  final numericMs = measure(() {
    for (var i = 0; i < 200000; i++) {
      checksum += SaleData.number(i / 10)!;
    }
  });
  final data = {
    'products': 20000,
    'searches': 100,
    'numeric_parses': 200000,
    'index_ms': indexMs,
    'search_ms': searchMs,
    'numeric_ms': numericMs,
    'checksum': checksum,
  };
  if (args.isNotEmpty) File(args.first).writeAsStringSync(jsonEncode(data));
  stdout.writeln(jsonEncode(data));
}
