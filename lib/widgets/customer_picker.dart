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
  });

  final List<dynamic> customers;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String placeholder;
  final String? label;

  Future<void> _open(BuildContext context) async {
    var matches = customers;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
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
                  onChanged: (text) => update(() {
                    final query = ProductCatalog.normalizeSearch(text);
                    matches = query.isEmpty
                        ? customers
                        : customers
                              .where(
                                (customer) => ProductCatalog.normalizeSearch(
                                  '${customer['name']} ${customer['code'] ?? ''} ${customer['phone'] ?? ''}',
                                ).contains(query),
                              )
                              .toList(growable: false);
                  }),
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
                      final customer = matches[index];
                      return ListTile(
                        title: Text(
                          '${customer['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${customer['code'] ?? ''} ${customer['type'] == 'supplier'
                                  ? 'مورد'
                                  : customer['type'] == 'both'
                                  ? 'زبون ومورد'
                                  : 'زبون'}'
                              .trim(),
                          maxLines: 1,
                        ),
                        onTap: () =>
                            Navigator.pop(context, SaleData.id(customer['id'])),
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
        ),
      ),
    );
    if (chosen != null) onChanged(chosen == 0 ? null : chosen);
  }

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
