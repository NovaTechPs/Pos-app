import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/product_add_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    Future<List<dynamic>> Function()? history,
    ValueChanged<ProductSelection?>? result,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final value = await showDialog<ProductSelection>(
                    context: context,
                    builder: (_) => ProductAddDialog(
                      product: const {
                        'id': 100234,
                        'name': 'بيبسي 330 مل',
                        'unit': 'كرتونة',
                      },
                      price: 65,
                      available: 20,
                      loadHistory: history,
                    ),
                  );
                  result?.call(value);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quantity and price remain a draft until confirmed, Arabic digits accepted',
    (tester) async {
      ProductSelection? result;
      await open(tester, result: (value) => result = value);
      await tester.enterText(
        find.byKey(const Key('add-product-quantity')),
        '١٠',
      );
      await tester.pump();
      expect(find.text('₪ 650.00'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(result?.quantity, 10);
      expect(result?.price, 65);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejects excess stock and cancellation does not add', (
    tester,
  ) async {
    ProductSelection? result;
    await open(tester, result: (value) => result = value);
    await tester.enterText(find.byKey(const Key('add-product-quantity')), '21');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('المتوفر 20'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('latest customer price opens above draft and can be applied', (
    tester,
  ) async {
    await open(
      tester,
      history: () async => [
        {'unit_price': 40, 'created_at': '2026-01-01'},
        {'unit_price': 60, 'created_at': '2026-11-09'},
      ],
    );
    await tester.tap(find.text('آخر سعر بيع لهذا الزبون'));
    await tester.pumpAndSettle();
    expect(find.text('₪ 60.00'), findsOneWidget);
    await tester.tap(find.text('استخدام هذا السعر'));
    await tester.pumpAndSettle();
    expect(find.text('60.00'), findsOneWidget);
    expect(find.text('إضافة إلى الفاتورة'), findsOneWidget);
  });

  testWidgets('history explains missing customer and network failure', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('آخر سعر بيع لهذا الزبون'));
    await tester.pumpAndSettle();
    expect(find.text('اختر الزبون أولاً لعرض آخر سعر بيع له'), findsOneWidget);
  });
}
