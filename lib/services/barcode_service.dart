class BarcodeService {
  static String normalize(Object? value) =>
      value?.toString().trim().toLowerCase() ?? '';

  /// APIs may return additional barcodes as objects or scalar values.
  static Iterable<String> codes(Map<dynamic, dynamic> product) sync* {
    final primary = normalize(product['barcode']);
    if (primary.isNotEmpty) yield primary;
    final aliases = product['barcodes'];
    if (aliases is! List) return;
    for (final alias in aliases) {
      final code = normalize(alias is Map ? alias['barcode'] : alias);
      if (code.isNotEmpty) yield code;
    }
  }

  static Map<String, dynamic>? findProduct(
    List<dynamic> categories,
    String value,
  ) {
    final code = normalize(value);
    if (code.isEmpty) return null;
    for (final category in categories) {
      for (final product in (category['products'] as List? ?? [])) {
        if (codes(product).contains(code)) {
          return Map<String, dynamic>.from(product);
        }
      }
    }
    return null;
  }
}
