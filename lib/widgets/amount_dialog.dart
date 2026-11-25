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
}) => showDialog<AmountEntry>(
  context: context,
  builder: (_) => _AmountDialog(
    title: title,
    label: label,
    allowZero: allowZero,
    initialAmount: initialAmount,
    details: details,
  ),
);

/// The dialog owns its fields, so they are disposed only after its closing animation ends.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.allowZero,
    required this.initialAmount,
    this.details,
  });

  final String title;
  final String label;
  final bool allowZero;
  final String initialAmount;
  final Widget? details;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _amount = TextEditingController(text: widget.initialAmount);
  final _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  var _submitted = false;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.details != null) ...[
                widget.details!,
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: widget.label),
                validator: (value) {
                  final number = SaleData.number(value);
                  return number == null ||
                          number < 0 ||
                          (!widget.allowZero && number == 0) ||
                          number > 9999999999.99
                      ? 'أدخل مبلغاً صحيحاً ${widget.allowZero ? 'غير سالب' : 'أكبر من صفر'}'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
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
          if (_submitted || !_form.currentState!.validate()) return;
          _submitted = true;
          Navigator.pop(
            context,
            AmountEntry(SaleData.number(_amount.text)!, _notes.text.trim()),
          );
        },
        child: const Text('تأكيد'),
      ),
    ],
  );
}
