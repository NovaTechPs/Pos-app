import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Blocks duplicate actions while the durable sale is being confirmed.
class CheckoutLoadingOverlay extends StatelessWidget {
  const CheckoutLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const ModalBarrier(dismissible: false, color: Color(0x990F172A)),
      Center(
        child: Semantics(
          liveRegion: true,
          label: 'جارٍ حفظ الفاتورة',
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/images/wasla-logo.svg',
                    width: 220,
                    height: 55,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'جارٍ حفظ الفاتورة…',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 150,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
