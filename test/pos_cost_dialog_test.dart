import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/pos_workspace.dart';

void main() {
  testWidgets('cost dialog lists each line like the web POS and totals it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCartCostDialog(context, [
              {
                'name': 'كاسات شاي',
                'quantity': 2,
                'price': 15,
                'cost_price': 12.5,
              },
              {
                'name': 'نافورة',
                'quantity': 1,
                'price': 0,
                'gift': true,
                'cost_price': 4,
              },
            ], 30),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-cost-dialog')), findsOneWidget);
    for (final header in [
      'الصنف',
      'الكمية',
      'السعر',
      'التكلفة',
      'إجمالي التكلفة',
      'الربح',
    ]) {
      expect(find.text(header), findsOneWidget);
    }
    final first = find.byKey(const Key('pos-cost-line-0'));
    for (final value in ['2', '15.00', '12.50', '25.00', '5.00']) {
      expect(
        find.descendant(of: first, matching: find.text(value)),
        findsOneWidget,
      );
    }
    final gift = find.byKey(const Key('pos-cost-line-1'));
    expect(
      find.descendant(of: gift, matching: find.text('نافورة — هدية')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: gift, matching: find.text('-4.00')),
      findsOneWidget,
    );
    expect(find.text('29.00'), findsOneWidget); // total cost
    expect(find.text('1.00'), findsOneWidget); // expected profit 30 - 29

    await tester.tap(find.byKey(const Key('pos-cost-dialog-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-cost-dialog')), findsNothing);
  });

  testWidgets('cost dialog warns when a line has no cost', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCartCostDialog(context, [
              {'name': 'صنف', 'quantity': 1, 'price': 10},
            ], 10),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('لم يرسل الخادم تكلفة جميع الأصناف؛ لا يمكن حساب الربح بدقة.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pos-cost-dialog-x')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-cost-dialog')), findsNothing);
  });
}
