import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/screens/employee_screen.dart';
import 'package:waslapos_app/screens/wholesale_screen.dart';
import 'package:waslapos_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ApiClient.client.close());
  const user = <String, dynamic>{'id': 1, 'tenant_id': 1, 'branch_id': 1};
  http.Response response(Object value) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  testWidgets(
    'employee attendance refreshes stale session data before clocking',
    (tester) async {
      String? clockType;
      ApiClient.client = MockClient((request) async {
        if (request.url.path.endsWith('/profile')) {
          return response({
            'employee': {'first_name': 'أحمد'},
            'today_attendance': null,
          });
        }
        if (request.url.path.endsWith('/clock')) {
          clockType = jsonDecode(request.body)['type'];
          return response({
            'attendance': {'check_in': '08:00'},
            'message': 'تم الحضور',
          });
        }
        return response({'payroll': [], 'advances': [], 'leaves': []});
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: EmployeeScreen(
            user: user,
            initialProfile: {
              'today_attendance': {'check_in': '08:00', 'check_out': '17:00'},
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('تسجيل الحضور'), findsOneWidget);
      await tester.tap(find.text('تسجيل الحضور'));
      await tester.pumpAndSettle();
      expect(clockType, 'check_in');
      expect(find.text('تسجيل الانصراف'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wholesale scanner waits for the complete code instead of selling its prefix',
    (tester) async {
      ApiClient.client = MockClient(
        (request) async => request.url.path.endsWith('/parties')
            ? response({'parties': []})
            : response({
                'products': [
                  {
                    'id': 1,
                    'name': 'صنف البادئة',
                    'barcode': '123',
                    'price': 10,
                    'stock_quantity': 10,
                    'min_wholesale_quantity': 1,
                  },
                  {
                    'id': 2,
                    'name': 'الصنف الكامل',
                    'barcode': '12345',
                    'price': 20,
                    'stock_quantity': 10,
                    'min_wholesale_quantity': 1,
                  },
                ],
              }),
      );
      await tester.pumpWidget(
        const MaterialApp(home: WholesaleScreen(user: user)),
      );
      await tester.pumpAndSettle();
      final input = find.byType(TextField).first;
      await tester.enterText(input, '123');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(input, '12345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('صنف البادئة'), findsOneWidget);
      expect(find.text('الصنف الكامل'), findsNWidgets(2));
      expect(find.text('1 أصناف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
