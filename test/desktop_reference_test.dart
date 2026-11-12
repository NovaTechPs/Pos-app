import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/screens/pos_shell.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/theme/app_theme.dart';
import 'package:waslapos_app/widgets/pos_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final config in [
    (density: 1.0, offline: false),
    (density: 1.25, offline: true),
    (density: 1.5, offline: true),
  ]) {
    testWidgets(
      'desktop fits at density ${config.density} with offline ${config.offline}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1920, 1000);
        tester.view.devicePixelRatio = config.density;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FlutterSecureStorage.setMockInitialValues({});
        await ApiClient.initialize();
        ApiClient.offline.value = config.offline;
        final font = File(r'C:\Windows\Fonts\segoeui.ttf');
        if (font.existsSync()) {
          for (final family in ['Segoe UI', 'PreviewArabic']) {
            final loader = FontLoader(family)
              ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              );
            await loader.load();
          }
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
        ApiClient.client = MockClient((request) async {
          final data = switch (request.url.path.split('/').last) {
            'active' => {
              'active_shift': {'id': 1},
            },
            'customers' => {'customers': []},
            'products' => {
              'categories': [
                {
                  'id': 1,
                  'name': 'الكل',
                  'products': List.generate(
                    40,
                    (i) => {
                      'id': i + 1,
                      'product_number': 1000 + i,
                      'name': [
                        'حاط فواكة مع مكان عسلي S23',
                        'إضاءة رمضان',
                        'إبريق بلاستيك شفاف',
                      ][i % 3],
                      'retail_price': i % 3 == 1 ? 10 : 75,
                      'stock_quantity': -2,
                      'barcode': '123$i',
                    },
                  ),
                },
              ],
            },
            _ => <String, dynamic>{},
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode(data)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        addTearDown(() => ApiClient.client.close());
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: RepaintBoundary(
                key: const Key('full-reference'),
                child: Column(
                  children: [
                    if (config.offline)
                      const Material(
                        color: Color(0xFFFEF3C7),
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: Text('دون اتصال — بيانات محفوظة على الجهاز'),
                          ),
                        ),
                      ),
                    Expanded(
                      child: PosShell(
                        user: const {
                          'id': 1,
                          'tenant_id': 1,
                          'branch_id': 1,
                          'name': 'Test Tenant User',
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('WaslaPOS'), findsNWidgets(2));
        expect(find.text('الصافي للدفع'), findsOneWidget);
        expect(find.text('إتمام البيع'), findsNothing);
        final logicalSize = tester.view.physicalSize / config.density;
        for (final key in [
          'pos-payment-footer',
          'pos-tool-الأصناف',
          'pos-tool-واتساب',
        ]) {
          final rect = tester.getRect(find.byKey(Key(key)));
          expect(
            rect.bottom,
            lessThanOrEqualTo(logicalSize.height + 1),
            reason: '$key must remain above the bottom edge',
          );
          expect(
            rect.left,
            greaterThanOrEqualTo(-1),
            reason: '$key must not be clipped on the left',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(logicalSize.width + 1),
            reason: '$key must not be clipped on the right',
          );
        }
        if (const bool.fromEnvironment('WRITE_UI_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('full-reference')),
            );
            final image = await boundary.toImage(pixelRatio: config.density);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory('tmp/ui').createSync(recursive: true);
            File(
              'tmp/ui/desktop-reference-${(config.density * 100).round()}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const Key('pos-tool-الأصناف')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('pos-catalog-search')))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        await tester.tap(
          find.text('حاط فواكة مع مكان عسلي S23').hitTestable().first,
        );
        await tester.pumpAndSettle();
        expect(find.text('قائمة الأصناف'), findsNothing);
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
          hasLength(1),
        );
        await tester.tap(find.text('بطاقة'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).paymentMethod,
          'card',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
