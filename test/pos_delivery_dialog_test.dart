import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/pos_workspace.dart';

void main() {
  Future<DeliveryDecision?> Function() openDialog(
    WidgetTester tester, {
    DeliveryDetails initial = const DeliveryDetails(),
  }) {
    DeliveryDecision? decision;
    var closed = false;
    late BuildContext context;
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (inner) {
              context = inner;
              return const Scaffold();
            },
          ),
        ),
      );
      showDeliveryDetailsDialog(
        context,
        initial: initial,
        parties: const [
          {
            'id': 7,
            'name': 'شركة توصيل هوك',
            'phone': '0593866661',
            'is_active': true,
          },
          {
            'id': 8,
            'name': 'مورد آخر',
            'phone': '0599111222',
            'is_active': true,
          },
          {'id': 9, 'name': 'شركة موقوفة', 'phone': '0590', 'is_active': false},
        ],
      ).then((value) {
        decision = value;
        closed = true;
      });
      await tester.pumpAndSettle();
      return closed ? decision : null;
    };
  }

  testWidgets(
    'the delivery window asks for every required field like the web',
    (tester) async {
      await openDialog(tester)();
      expect(find.text('بيانات التوصيل'), findsOneWidget);
      expect(
        find.text('هذه البيانات ستظهر وتحفظ مع الفاتورة.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('pos-delivery-save-print')));
      await tester.pumpAndSettle();

      expect(find.text('حقل الاسم مطلوب.'), findsOneWidget);
      expect(find.text('حقل رقم الهاتف مطلوب.'), findsOneWidget);
      expect(find.text('حقل المكان / العنوان مطلوب.'), findsOneWidget);
      expect(find.text('اختر شركة التوصيل.'), findsOneWidget);
      expect(find.byKey(const Key('pos-delivery-dialog')), findsOneWidget);
    },
  );

  testWidgets('the cashier picks the delivery company and saves and prints', (
    tester,
  ) async {
    DeliveryDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    decision = await showDeliveryDetailsDialog(
                      context,
                      initial: const DeliveryDetails(
                        name: 'أبو أحمد',
                        phone: '0599000111',
                      ),
                      parties: const [
                        {
                          'id': 7,
                          'name': 'شركة توصيل هوك',
                          'phone': '0593866661',
                          'is_active': true,
                        },
                        {
                          'id': 9,
                          'name': 'شركة موقوفة',
                          'phone': '0590',
                          'is_active': false,
                        },
                      ],
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'أبو أحمد'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('pos-delivery-address')),
      'الخليل - رأس الجورة',
    );
    await tester.enterText(
      find.byKey(const Key('pos-delivery-notes')),
      'اتصل قبل الوصول',
    );
    await tester.enterText(
      find.byKey(const Key('pos-delivery-company')),
      'شركة',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-delivery-company-7')), findsOneWidget);
    expect(
      find.byKey(const Key('pos-delivery-company-9')),
      findsNothing,
      reason: 'inactive accounts are not offered',
    );
    await tester.tap(find.byKey(const Key('pos-delivery-company-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-delivery-save-print')));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.print, isTrue);
    expect(decision!.details.toPayload(), {
      'delivery_customer_name': 'أبو أحمد',
      'delivery_customer_phone': '0599000111',
      'delivery_customer_address': 'الخليل - رأس الجورة',
      'delivery_notes': 'اتصل قبل الوصول',
      'delivery_party_id': 7,
    });
  });

  testWidgets('save alone does not print', (tester) async {
    DeliveryDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => decision = await showDeliveryDetailsDialog(
                context,
                initial: const DeliveryDetails(
                  name: 'مستلم',
                  phone: '0590000000',
                  address: 'الخليل',
                  companyId: 7,
                  companyName: 'شركة توصيل هوك',
                ),
                parties: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-delivery-save')));
    await tester.pumpAndSettle();

    expect(decision?.print, isFalse);
    expect(decision?.details.isComplete, isTrue);
  });
}
