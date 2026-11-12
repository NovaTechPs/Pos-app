import 'package:flutter/material.dart';

import '../services/checkout_service.dart';

/// Only confirmed results are resolved automatically; absence never permits a retry.
Future<bool?> reviewOperation(
  BuildContext context,
  CheckoutService service,
) async {
  try {
    if (await service.reconcile()) return true;
  } catch (_) {
    // A failed lookup leaves the durable journal unchanged.
  }
  if (!context.mounted) return null;
  final record = await service.read();
  if (!context.mounted || !CheckoutService.needsReview(record)) return null;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تحقق من العملية السابقة'),
      content: Text(
        'لم يتأكد التطبيق من النتيجة. راجع الفاتورة في سجل الخادم قبل الاختيار. لا تعد الإرسال اعتماداً على فقد الرد فقط.\nرقم العملية: ${record?['payload']?['operation_uuid']}\nالتاريخ: ${record?['created_at']}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('لاحقاً'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('تحققت: محفوظة'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('تحققت: غير محفوظة'),
        ),
      ],
    ),
  );
  if (saved != null) await service.resolveAfterVerification(wasSaved: saved);
  return saved;
}
