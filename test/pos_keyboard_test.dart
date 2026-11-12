import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/pos_keyboard.dart';

void main() {
  testWidgets(
    'RTL cart arrows wrap rows, preserve columns and return to barcode',
    (tester) async {
      final keyboard = PosCartKeyboard();
      final barcode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: barcode),
                for (var row = 0; row < 2; row++)
                  for (var col = 0; col < 3; col++)
                    PosNumberCell(
                      value: 1,
                      node: keyboard.node(row, col),
                      onValue: (_) {},
                      onKey: (event) =>
                          keyboard.handle(event, row, col, 2, barcode),
                    ),
              ],
            ),
          ),
        ),
      );
      keyboard.focus(1, 2);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(keyboard.node(0, 0).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(keyboard.node(1, 2).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(keyboard.node(0, 2).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(keyboard.node(1, 2).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(keyboard.node(0, 2).hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(barcode.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
      keyboard.dispose();
      barcode.dispose();
    },
  );
}
