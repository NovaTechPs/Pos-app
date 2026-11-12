import 'package:flutter/material.dart';

Future<void> showPaymentMismatch(
  BuildContext context,
  num requested,
  Object? actual,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) => AlertDialog(
    title: const Text('اختلاف في الدفعة المسجلة'),
    content: Text(
      'حُفظت العملية، لكن الدفعة المرسلة ${requested.toStringAsFixed(2)} والدفعة التي أعادها الخادم ${actual ?? "غير متوفرة"}. راجع الفاتورة أو السند على الخادم قبل تسجيل دفعة أخرى. لم تُعد العملية تلقائياً.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('فهمت'),
      ),
    ],
  ),
);
