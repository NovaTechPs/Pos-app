import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/pos_workspace.dart';
import 'package:waslapos_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('PreviewArabic')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            (File(r'C:\Windows\Fonts\segoeui.ttf').existsSync()
                    ? File(r'C:\Windows\Fonts\segoeui.ttf')
                    : File('assets/fonts/Amiri-Regular.ttf'))
                .readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    if (File(r'C:\Windows\Fonts\consolab.ttf').existsSync()) {
      final numbers = FontLoader('Consolas')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(r'C:\Windows\Fonts\consolab.ttf').readAsBytesSync(),
            ),
          ),
        );
      await numbers.load();
    }
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
  });

  for (final size in [
    const Size(390, 844),
    const Size(800, 600),
    const Size(1280, 900),
    const Size(1920, 906),
  ]) {
    testWidgets(
      'POS catalog and cart fit ${size.width.toInt()}px without overflow',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        final theme = const bool.fromEnvironment('WRITE_UI_PREVIEWS')
            ? AppTheme.light.copyWith(
                textTheme: AppTheme.light.textTheme.apply(
                  fontFamily: 'PreviewArabic',
                ),
              )
            : AppTheme.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: const Key('preview'),
              child: Scaffold(
                body: Directionality(
                  textDirection: TextDirection.rtl,
                  child: PosWorkspace(
                    products: List.generate(
                      12,
                      (i) => {
                        'id': i,
                        'name': [
                          'قهوة عربية محمصة',
                          'شاي بالنعناع',
                          'علبة حليب طازج',
                        ][i % 3],
                      },
                    ),
                    categories: const [
                      {'id': 1, 'name': 'المشروبات'},
                      {'id': 2, 'name': 'المواد الغذائية'},
                    ],
                    customers: const [
                      {'id': 1, 'name': 'شركة الاختبار'},
                    ],
                    cart: const [
                      {
                        'name': 'قهوة عربية محمصة',
                        'quantity': 2.0,
                        'price': 15.0,
                        'discount': 0.0,
                      },
                    ],
                    barcodeController: controller,
                    barcodeFocus: focus,
                    selectedCategoryId: null,
                    customerId: null,
                    subtotal: 30,
                    discount: 0,
                    tax: 0,
                    total: 30,
                    paymentMethod: 'cash',
                    cashier: 'أحمد',
                    shiftId: 1,
                    priceFor: (_) => 15,
                    onBarcode: (_) {},
                    onSubmitBarcode: (_) {},
                    onScan: () {},
                    onCategory: (_) {},
                    onCustomer: (_) {},
                    onAdd: (_) => true,
                    onQuantity: (_, _) {},
                    onRemove: (_) {},
                    onDiscount: (_) {},
                    onPayment: (_) {},
                    onCheckout: () {},
                    onHold: () {},
                    onHeld: () {},
                    onClear: () {},
                    actions: const {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('WRITE_UI_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('preview')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory('tmp/ui').createSync(recursive: true);
            File('tmp/ui/pos-${size.width.toInt()}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (size.width < 1050) {
          await tester.tap(find.text('السلة (1)'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
