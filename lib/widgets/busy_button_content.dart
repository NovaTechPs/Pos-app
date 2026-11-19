import 'package:flutter/material.dart';

/// Button content that turns into a spinner and «جاري ...» while its action runs,
/// so the user sees the press was taken and does not press again.
class BusyButtonContent extends StatelessWidget {
  const BusyButtonContent({
    super.key,
    required this.busy,
    required this.label,
    required this.busyLabel,
    this.icon,
  });

  final bool busy;
  final String label;
  final String busyLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
          )
        else if (icon != null)
          Icon(icon, size: 20),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(busy ? busyLabel : label),
      ],
    );
  }
}
