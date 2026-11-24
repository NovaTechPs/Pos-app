import 'package:flutter/material.dart';

import '../models/product_catalog.dart';
import '../models/sale_data.dart';

/// Only the selected customer is laid out on the sale screen.
class CustomerPicker extends StatelessWidget {
  const CustomerPicker({
    super.key,
    required this.customers,
    required this.value,
    required this.onChanged,
    this.placeholder = 'عميل نقدي',
    this.label,
    this.onRefresh,
    this.appearance,
  });

  final List<dynamic> customers;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String placeholder;
  final String? label;
  final Future<List<dynamic>> Function()? onRefresh;

  /// Draws the closed picker from the shown name and whether a customer is chosen (the desktop POS
  /// uses the web «إضافة زبون للفاتورة» button); the dropdown field is used when null.
  final Widget Function(String name, bool chosen)? appearance;

  Future<void> _open(BuildContext context) async {
    final refreshFuture = onRefresh?.call();
    var query = '';
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => FutureBuilder<List<dynamic>>(
          future: refreshFuture,
          builder: (context, snapshot) {
            final entries = (snapshot.data ?? customers)
                .whereType<Map>()
                .map(_CustomerSearchEntry.fromMap)
                .toList(growable: false);
            final matches = _search(entries, query);
            final isRefreshing =
                snapshot.connectionState == ConnectionState.waiting;

            return AlertDialog(
              title: const Text('اختيار الزبون أو المورد'),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'بحث بالاسم أو الرمز أو الهاتف',
                      ),
                      onChanged: (value) => update(() => query = value),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Text(
                              'النتائج: ${matches.length} من ${entries.length}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (isRefreshing) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'تعذر تحديث القائمة؛ تظهر النسخة المحفوظة.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ListTile(
                      title: const Text('عميل نقدي'),
                      onTap: () => Navigator.pop(context, 0),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemExtent: 56,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final customer = matches[index].customer;
                          final details = [
                            '${customer['code'] ?? ''}'.trim(),
                            '${customer['phone'] ?? ''}'.trim(),
                            _partyTypeLabel(customer['type']),
                          ].where((value) => value.isNotEmpty).join(' • ');
                          return ListTile(
                            title: Text(
                              '${customer['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(details, maxLines: 1),
                            onTap: () => Navigator.pop(
                              context,
                              SaleData.id(customer['id']),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (chosen != null) onChanged(chosen == 0 ? null : chosen);
  }

  static List<_CustomerSearchEntry> _search(
    List<_CustomerSearchEntry> entries,
    String value,
  ) {
    final query = ProductCatalog.normalizeSearch(value);
    final digitQuery = _digitsOnly(value);
    if (query.isEmpty && digitQuery.isEmpty) {
      return entries;
    }

    final matches = entries
        .where((entry) => entry.matches(query, digitQuery))
        .toList(growable: false);
    matches.sort((left, right) {
      final rank = left
          .rank(query, digitQuery)
          .compareTo(right.rank(query, digitQuery));
      return rank != 0 ? rank : left.name.compareTo(right.name);
    });

    return matches;
  }

  static String _partyTypeLabel(Object? type) => switch (type) {
    'supplier' => 'مورد',
    'both' => 'زبون ومورد',
    _ => 'زبون',
  };

  static String _digitsOnly(String value) => value
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll('۰', '0')
      .replaceAll('۱', '1')
      .replaceAll('۲', '2')
      .replaceAll('۳', '3')
      .replaceAll('۴', '4')
      .replaceAll('۵', '5')
      .replaceAll('۶', '6')
      .replaceAll('۷', '7')
      .replaceAll('۸', '8')
      .replaceAll('۹', '9')
      .replaceAll(RegExp('[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    var name = value == null ? placeholder : 'عميل #$value';
    if (value != null) {
      for (final customer in customers) {
        if (SaleData.id(customer['id']) == value) {
          name = '${customer['name']}';
          break;
        }
      }
    }
    if (appearance != null) {
      return InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: appearance!(name, value != null),
      );
    }
    return InkWell(
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchEntry {
  const _CustomerSearchEntry({
    required this.customer,
    required this.name,
    required this.searchText,
    required this.numericValues,
  });

  factory _CustomerSearchEntry.fromMap(Map customer) {
    final values = [
      '${customer['name'] ?? ''}',
      '${customer['code'] ?? ''}',
      '${customer['phone'] ?? ''}',
      '${customer['email'] ?? ''}',
      '${customer['tax_number'] ?? ''}',
      '${customer['id'] ?? ''}',
    ];

    return _CustomerSearchEntry(
      customer: customer,
      name: ProductCatalog.normalizeSearch('${customer['name'] ?? ''}'),
      searchText: ProductCatalog.normalizeSearch(values.join(' ')),
      numericValues: values
          .map(CustomerPicker._digitsOnly)
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  final Map customer;
  final String name;
  final String searchText;
  final List<String> numericValues;

  bool matches(String query, String digitQuery) =>
      (query.isNotEmpty && ProductCatalog.matchesWords(searchText, query)) ||
      (digitQuery.isNotEmpty &&
          numericValues.any((value) => value.contains(digitQuery)));

  int rank(String query, String digitQuery) {
    final exact =
        query.isNotEmpty && searchText == query ||
        digitQuery.isNotEmpty && numericValues.contains(digitQuery);
    if (exact) {
      return 0;
    }

    final startsWith =
        query.isNotEmpty && searchText.startsWith(query) ||
        digitQuery.isNotEmpty &&
            numericValues.any((value) => value.startsWith(digitQuery));
    return startsWith ? 1 : 2;
  }
}
