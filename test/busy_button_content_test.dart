import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/busy_button_content.dart';

void main() {
  testWidgets('a button shows a spinner and «جاري ...» while its action runs', (
    tester,
  ) async {
    Widget button(bool busy) => MaterialApp(
      home: Scaffold(
        body: FilledButton(
          onPressed: busy ? null : () {},
          child: BusyButtonContent(
            busy: busy,
            icon: Icons.save,
            label: 'حفظ',
            busyLabel: 'جاري الحفظ…',
          ),
        ),
      ),
    );

    await tester.pumpWidget(button(false));
    expect(find.text('حفظ'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(button(true));
    expect(find.text('جاري الحفظ…'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
