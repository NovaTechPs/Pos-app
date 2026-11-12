import 'package:flutter/material.dart';

import '../models/sale_data.dart';

class AmountEntry {
  const AmountEntry(this.amount, this.notes);
  final double amount;
  final String notes;
}

Future<AmountEntry?> showAmountDialog(
  BuildContext context, {
  required String title,
  required String label,
  bool allowZero = false,
  String initialAmount = '',
  Widget? details,
}) async {
  final amount = TextEditingController(text: initialAmount);
  final notes = TextEditingController();
  final form = GlobalKey<FormState>();
  var submitted = false;
  try {
    return await showDialog<AmountEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (details != null) ...[details, const SizedBox(height: 16)],
                  TextFormField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: label),
                    validator: (value) {
                      final number = SaleData.number(value);
                      return number == null ||
                              number < 0 ||
                              (!allowZero && number == 0) ||
                              number > 9999999999.99
                          ? 'أدخل مبلغاً صحيحاً ${allowZero ? 'غير سالب' : 'أكبر من صفر'}'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'البيان / ملاحظات',
                    ),
                  ),
                ],
              ),
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
              if (submitted || !form.currentState!.validate()) return;
              submitted = true;
              Navigator.pop(
                context,
                AmountEntry(SaleData.number(amount.text)!, notes.text.trim()),
              );
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  } finally {
    amount.dispose();
    notes.dispose();
  }
}
