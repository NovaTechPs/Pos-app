import '../services/barcode_service.dart';
import 'sale_data.dart';

/// A screen-local index, replaced whenever prices or catalog data are refreshed.
class ProductCatalog {
  ProductCatalog(List<dynamic> categories) {
    for (final category in categories) {
      final categoryId = SaleData.id(category['id']);
      final members = <dynamic>[];
      for (final product in (category['products'] as List? ?? const [])) {
        final codes = BarcodeService.codes(product).toList(growable: false);
        final entry = _Entry(
          product,
          normalizeSearch(
            '${product['name']} ${product['id']} ${product['product_number'] ?? ''}',
          ),
          codes,
        );
        _entries.add(entry);
        members.add(product);
        for (final code in codes) {
          _barcodes.putIfAbsent(code, () => product);
        }
      }
      (_categories[categoryId] ??= []).addAll(members);
    }
    _all = List<dynamic>.unmodifiable(_entries.map((entry) => entry.product));
    final codes = _barcodes.keys.toList()..sort();
    for (var i = 0; i + 1 < codes.length; i++) {
      if (codes[i + 1].startsWith(codes[i])) _barcodePrefixes.add(codes[i]);
    }
  }

  final _entries = <_Entry>[];
  final _categories = <int?, List<dynamic>>{};
  final _barcodes = <String, dynamic>{};
  final _barcodePrefixes = <String>{};
  bool isCompleteBarcode(String value) {
    final code = BarcodeService.normalize(value);
    return _barcodes.containsKey(code) && !_barcodePrefixes.contains(code);
  }

  late final List<dynamic> _all;
  String? _lastQuery;
  int? _lastCategory;
  List<dynamic>? _lastResult;

  Map<String, dynamic>? findBarcode(String code) {
    final product = _barcodes[BarcodeService.normalize(code)];
    return product == null ? null : Map<String, dynamic>.from(product);
  }

  List<dynamic> search(String value, int? categoryId) {
    final query = normalizeSearch(value);
    if (_lastResult != null &&
        query == _lastQuery &&
        categoryId == _lastCategory) {
      return _lastResult!;
    }
    _lastQuery = query;
    _lastCategory = categoryId;
    final words = query.split(' ');
    return _lastResult = query.isEmpty
        ? (categoryId == null ? _all : _categories[categoryId] ?? const [])
        : _byStock(
            _entries
                .where(
                  (entry) =>
                      words.every(entry.name.contains) ||
                      entry.codes.any((code) => code.contains(query)),
                )
                .toList(),
            query,
          );
  }

  /// Exact barcode or product number first (a scan stays on top), then from the
  /// most to the least stock in this branch; items with none in the branch follow,
  /// from the most to the least shared stock. Equal items keep their catalog order.
  static List<dynamic> _byStock(List<_Entry> matches, String query) {
    int exact(_Entry entry) =>
        entry.codes.contains(query) ||
            normalizeSearch('${entry.product['product_number'] ?? ''}') == query
        ? 0
        : 1;
    double local(_Entry entry) =>
        SaleData.number(entry.product['stock_quantity']) ?? 0;
    int tier(_Entry entry) => local(entry) > 0 ? 0 : 1;
    double stock(_Entry entry) => local(entry) > 0
        ? local(entry)
        : SaleData.number(entry.product['shared_stock_quantity']) ?? 0;
    final ranked = [for (var i = 0; i < matches.length; i++) (i, matches[i])];
    ranked.sort((a, b) {
      final byExact = exact(a.$2).compareTo(exact(b.$2));
      if (byExact != 0) return byExact;
      final byTier = tier(a.$2).compareTo(tier(b.$2));
      if (byTier != 0) return byTier;
      final byStock = stock(b.$2).compareTo(stock(a.$2));
      return byStock != 0 ? byStock : a.$1.compareTo(b.$1);
    });
    return List<dynamic>.unmodifiable(ranked.map((item) => item.$2.product));
  }

  /// True when every word of an already normalized [query] appears in [text], in any order,
  /// the same way the product search matches (\u00AB\u0628\u064A\u0628\u0633\u064A \u0644\u062A\u0631\u00BB finds \u00AB\u0644\u062A\u0631 \u0628\u064A\u0628\u0633\u064A\u00BB).
  static bool matchesWords(String text, String query) {
    if (query.isEmpty) return true;
    return query.split(' ').every(text.contains);
  }

  static final _marks = RegExp(r'[\u064B-\u065F\u0670\u0640]');
  static final _alef = RegExp('[أإآٱ]');
  static final _spaces = RegExp(r'\s+');
  static String normalizeSearch(String value) => value
      .toLowerCase()
      .replaceAll(_marks, '')
      .replaceAll(_alef, 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(_spaces, ' ')
      .trim();
}

class _Entry {
  const _Entry(this.product, this.name, this.codes);
  final dynamic product;
  final String name;
  final List<String> codes;
}
