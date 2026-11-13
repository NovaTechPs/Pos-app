import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/theme/app_theme.dart';
import 'package:waslapos_app/widgets/popup_arrow_navigation.dart';

/// The keyboard-focused button in a popup must be obvious (outer ring).
void main() {
  testWidgets('focused popup buttons get a clear outer ring', (tester) async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Segoe UI')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    tester.view.physicalSize = const Size(520, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        navigatorObservers: [PopupAutoFocusObserver(enabled: true)],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: PopupArrowNavigation(
            child: RepaintBoundary(key: const Key('shot'), child: child!),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('تأكيد إفراغ الفاتورة'),
                  content: const Text(
                    'هل تريد إفراغ الفاتورة الحالية وبدء فاتورة جديدة؟',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('إفراغ الفاتورة'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Keyboard use switches Flutter to the "show focus" highlight mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      if (!const bool.fromEnvironment('WRITE_UI_PREVIEWS')) return;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shot')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('tmp/ui/$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    BorderSide? ringOf(String label) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      final shape = material.shape;
      return shape is OutlinedBorder ? shape.side : null;
    }

    // Cancel is focused on open and shows the ring; the other does not.
    expect(ringOf('إلغاء')?.color, AppTheme.focusRingColor);
    expect(ringOf('إفراغ الفاتورة')?.color, isNot(AppTheme.focusRingColor));
    await shot('focus-ring-cancel');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(ringOf('إفراغ الفاتورة')?.color, AppTheme.focusRingColor);
    expect(ringOf('إلغاء')?.color, isNot(AppTheme.focusRingColor));
    await shot('focus-ring-confirm');
  });
}
