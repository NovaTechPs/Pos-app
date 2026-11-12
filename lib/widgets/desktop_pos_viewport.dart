import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the dense desktop workspace inside the window at Windows display zoom.
class DesktopPosViewport extends StatelessWidget {
  const DesktopPosViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1050) return child;
      final media = MediaQuery.of(context);
      final physicalWidth = constraints.maxWidth * media.devicePixelRatio;
      final designWidth = math.max(
        constraints.maxWidth,
        math.min(1920.0, physicalWidth),
      );
      final scale = math.max(
        designWidth / constraints.maxWidth,
        900 / constraints.maxHeight,
      );
      final size = Size(
        constraints.maxWidth * scale,
        constraints.maxHeight * scale,
      );
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: MediaQuery(
              data: media.copyWith(size: size),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
