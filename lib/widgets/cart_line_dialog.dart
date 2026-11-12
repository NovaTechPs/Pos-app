import 'package:flutter/material.dart';

import '../models/sale_data.dart';

class CartLineEntry {
  const CartLineEntry(this.quantity, this.price);
  final double quantity, price;
}

Future<CartLineEntry?> showCartLineDialog(
  BuildContext context,
  Map<String, dynamic> line,
) async {
  final quantity = TextEditingController(text: '${line['quantity']}');
  final price = TextEditingController(
    text:
        '${SaleData.number(line['price'])! - (SaleData.number(line['discount']) ?? 0)}',
  );
  final form = GlobalKey<FormState>();
  final gift = line['gift'] == true;
  try {
    return await showDialog<CartLineEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل ${line['name']}'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('pos-line-quantity'),
                  controller: quantity,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (text) {
                    final value = SaleData.number(text);
                    return value == null || value < .01 || value > 999999999
                        ? 'أدخل كمية لا تقل عن 0.01'
                        : null;
                  },
                ),
                TextFormField(
                  key: const Key('pos-line-price'),
                  controller: price,
                  enabled: !gift,
                  decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (text) {
                    final value = SaleData.number(text);
                    return value == null || value < 0 || value > 999999999
                        ? 'أدخل سعراً غير سالب'
                        : null;
                  },
                ),
                if (gift) const Text('هدية — سعرها صفر، ويمكن تعديل كميتها.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  CartLineEntry(
                    SaleData.number(quantity.text)!,
                    gift ? 0 : SaleData.number(price.text)!,
                  ),
                );
              }
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    quantity.dispose();
    price.dispose();
  }
}

Future<void> showCartCostDialog(
  BuildContext context,
  List<Map<String, dynamic>> cart,
  double total,
) async {
  final missing =
      cart.isEmpty ||
      cart.any((line) => SaleData.number(line['cost_price']) == null);
  final cost = cart.fold<double>(
    0,
    (sum, line) =>
        sum +
        (SaleData.number(line['cost_price']) ?? 0) *
            SaleData.number(line['quantity'])!,
  );
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تحليل التكلفة والربح'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in cart)
                ListTile(
                  title: Text(
                    '${line['name']}${line['gift'] == true ? ' — هدية' : ''}',
                  ),
                  subtitle: Text('الكمية: ${line['quantity']}'),
                  trailing: Text(
                    SaleData.number(line['cost_price']) == null
                        ? 'غير متاحة'
                        : (SaleData.number(line['cost_price'])! *
                                  SaleData.number(line['quantity'])!)
                              .toStringAsFixed(2),
                  ),
                ),
              if (missing)
                const Text(
                  'لم يرسل الخادم تكلفة جميع الأصناف؛ لا يمكن حساب الربح بدقة.',
                )
              else ...[
                Text('إجمالي التكلفة: ${cost.toStringAsFixed(2)}'),
                Text('الربح بعد الخصم: ${(total - cost).toStringAsFixed(2)}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
