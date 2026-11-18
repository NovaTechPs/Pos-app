import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/customer_picker.dart';

void main() {
  testWidgets(
    'large customer lists build only visible rows and search selects correctly',
    (tester) async {
      final customers = List.generate(
        20000,
        (index) => {'id': index + 1, 'name': 'Customer $index'},
      );
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerPicker(
              customers: customers,
              value: null,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      expect(find.byType(ListTile), findsNothing);
      await tester.tap(find.text('عميل نقدي'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(25));
      await tester.enterText(find.byType(TextField), 'Customer 19999');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer 19999').last);
      await tester.pumpAndSettle();
      expect(selected, 20000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer search keeps the full list and finds normalized phone and code',
    (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerPicker(
              customers: const [
                {
                  'id': 1,
                  'name': 'أحمد التجارة',
                  'code': 'C000001',
                  'phone': '059-123 4567',
                },
                {
                  'id': 2,
                  'name': 'منى للمواد',
                  'code': 'C000002',
                  'phone': '059-222 3333',
                },
                {
                  'id': 3,
                  'name': 'سعيد',
                  'code': 'C000003',
                  'phone': '059-444 5555',
                },
              ],
              value: null,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      );

      await tester.tap(find.text('عميل نقدي'));
      await tester.pumpAndSettle();
      expect(find.text('النتائج: 3 من 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '٠٥٩١٢٣٤٥٦٧');
      await tester.pumpAndSettle();
      expect(find.text('أحمد التجارة'), findsOneWidget);
      expect(find.text('منى للمواد'), findsNothing);

      await tester.tap(find.text('أحمد التجارة'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    },
  );

  testWidgets('customer picker refreshes its list while keeping the search', (
    tester,
  ) async {
    final refreshedCustomers = Completer<List<dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerPicker(
            customers: const [
              {'id': 1, 'name': 'قائمة قديمة'},
            ],
            value: null,
            onChanged: (_) {},
            onRefresh: () => refreshedCustomers.future,
          ),
        ),
      ),
    );

    await tester.tap(find.text('عميل نقدي'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ستوب');
    await tester.pump();
    expect(find.text('النتائج: 0 من 1'), findsOneWidget);

    refreshedCustomers.complete([
      {'id': 228, 'name': 'ستوب ستوك / كفر عقب', 'code': 'C00000228'},
    ]);
    await tester.pumpAndSettle();

    expect(find.text('النتائج: 1 من 1'), findsOneWidget);
    expect(find.text('ستوب ستوك / كفر عقب'), findsOneWidget);
  });
}
