import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/screens/barcode_labels_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'label catalog preserves code case and zeros, fills web fields and refreshes API',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await ApiClient.initialize();
      await ApiClient.saveSession(
        token: 'labels-test',
        session: {
          'user': {'id': 1, 'tenant_id': 1, 'branch_id': 1},
        },
      );
      var requests = 0;
      ApiClient.client = MockClient((_) async {
        requests++;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'categories': [
                {
                  'id': 1,
                  'products': [
                    {
                      'id': 42,
                      'product_number': 'P-42',
                      'name': 'قهوة عربية',
                      'cost_price': 8.5,
                      'barcode': '00AbC123',
                      'barcodes': [
                        {'barcode': '0000456'},
                      ],
                    },
                  ],
                },
              ],
            }),
          ),
          200,
        );
      });
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: BarcodeLabelsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-product-42')));
      await tester.pumpAndSettle();
      String value(String label) => tester
          .widget<TextField>(find.byKey(ValueKey(label)))
          .controller!
          .text;
      expect(value('الباركود'), '00AbC123');
      expect(value('اسم الصنف (اختياري)'), 'قهوة عربية');
      expect(value('السعر المطبوع (التكلفة كما في الويب)'), '8.50');
      expect(value('رقم الصنف'), 'P-42');
      expect(value('الارتفاع بالملم'), '25');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0000456').last);
      await tester.pumpAndSettle();
      expect(value('الباركود'), '0000456');
      await tester.tap(find.text('تحديث قائمة الأصناف'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      ApiClient.client.close();
    },
  );
}
