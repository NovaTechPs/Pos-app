import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/widgets/missing_barcode_dialog.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.initialize();
  });
  tearDown(() => ApiClient.client.close());
  Future<void> show(
    WidgetTester tester, {
    ValueChanged<Map<String, dynamic>?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const MissingBarcodeDialog(
                    barcode: '00AbC',
                    branchId: 1,
                    categories: [],
                    products: [
                      {'id': 21, 'name': 'قهوة', 'barcode': '00123'},
                    ],
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'missing barcode choice fits $width and Escape cancels without requests',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var writes = 0;
        ApiClient.client = MockClient((_) async {
          writes++;
          return http.Response('{}', 500);
        });
        await show(tester);
        expect(find.text('00AbC'), findsOneWidget);
        expect(find.text('نعم'), findsOneWidget);
        expect(find.text('لا'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(MissingBarcodeDialog), findsNothing);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'scanner Enter suffixes leave the choice visible until an explicit selection',
    (tester) async {
      var writes = 0;
      ApiClient.client = MockClient((_) async {
        writes++;
        return http.Response('{}', 500);
      });
      await show(tester);
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.text('نعم'), findsOneWidget);
        expect(find.text('لا'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
      }
      expect(writes, 0);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'بحث عن صنف موجود'),
        findsOneWidget,
      );
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'No searches existing products and attaches the exact barcode once',
    (tester) async {
      Map<String, dynamic>? body, result;
      var writes = 0;
      ApiClient.client = MockClient((request) async {
        writes++;
        expect(request.url.path, endsWith('/pos/product-barcodes'));
        body = Map<String, dynamic>.from(jsonDecode(request.body));
        return http.Response(
          '{"product":{"id":21,"name":"Coffee","barcodes":[{"barcode":"00AbC"}]}}',
          200,
        );
      });
      await show(tester, onResult: (value) => result = value);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'قهوة');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'قهوة'));
      await tester.pumpAndSettle();
      expect(body, {'branch_id': 1, 'product_id': 21, 'barcode': '00AbC'});
      expect(writes, 1);
      expect(result?['id'], 21);
      expect(find.byType(MissingBarcodeDialog), findsNothing);
    },
  );

  testWidgets('deliberately focusing Yes still permits keyboard selection', (
    tester,
  ) async {
    await show(tester);
      Focus.of(tester.element(find.text('نعم'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(5));
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Yes validates a new product and keeps its form on server rejection',
    (tester) async {
      var writes = 0;
      var accept = false;
      Map<String, dynamic>? result;
      ApiClient.client = MockClient((request) async {
        writes++;
        final data = jsonDecode(request.body) as Map;
        expect(data['barcode'], '00AbC');
        expect(data['name'], 'New product');
        expect(data['retail_price'], 12);
        if (accept) {
          return http.Response(
            '{"product":{"id":44,"name":"New product"}}',
            201,
          );
        }
        return http.Response.bytes(
          utf8.encode('{"errors":{"barcode":["الباركود مستخدم"]}}'),
          422,
          headers: {'content-type': 'application/json'},
        );
      });
      await show(tester, onResult: (value) => result = value);
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ الصنف'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.enterText(find.byType(TextFormField).at(0), 'New product');
      await tester.ensureVisible(find.byType(TextFormField).at(2));
      await tester.enterText(find.byType(TextFormField).at(2), '12');
      await tester.tap(find.text('حفظ الصنف'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('الباركود مستخدم'), findsOneWidget);
      expect(find.byType(MissingBarcodeDialog), findsOneWidget);
      accept = true;
      await tester.tap(find.text('حفظ الصنف'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(result?['id'], 44);
      expect(find.byType(MissingBarcodeDialog), findsNothing);
    },
  );

  testWidgets(
    'offline linking reports that the server is required without sending',
    (tester) async {
      ApiClient.offline.value = true;
      var writes = 0;
      ApiClient.client = MockClient((_) async {
        writes++;
        return http.Response('{}', 500);
      });
      await show(tester);
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'قهوة');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'قهوة'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.textContaining('يتطلبان الاتصال بالخادم'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
    },
  );
}
