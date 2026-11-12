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
}
