import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/wholesale_cart_line.dart';
import 'package:waslapos_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'inline cart fits mobile and steppers preserve directly edited prices',
    (tester) async {
      tester.view.physicalSize = const Size(360, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('RowArabic')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                  .readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
      var price = 50.0, quantity = 1.0;
      var valid = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightFor(
            'blue',
          ).copyWith(textTheme: ThemeData(fontFamily: 'RowArabic').textTheme),
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: const Key('row-preview'),
                  child: StatefulBuilder(
                    builder: (context, update) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: WholesaleCartLine(
                          id: 1,
                          name: 'إبريق شاي توتيا 2.5 لتر ثقيل',
                          price: price,
                          quantity: quantity,
                          minimum: 1,
                          available: 10,
                          allowNegative: false,
                          enabled: true,
                          onChanged: (p, q) => update(() {
                            price = p;
                            quantity = q;
                          }),
                          onValidity: (value) => valid = value,
                          onHistory: () {},
                          onRemove: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('wholesale-price-1')),
        '45',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('زيادة الكمية'));
      await tester.pumpAndSettle();
      expect(price, 45);
      expect(quantity, 2);
      expect(find.text('90.00'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('row-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/wholesale-cart-inline-preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.enterText(
        find.byKey(const ValueKey('wholesale-quantity-1')),
        '٢٫٥',
      );
      await tester.pumpAndSettle();
      expect(quantity, 2.5);
      expect(valid, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
