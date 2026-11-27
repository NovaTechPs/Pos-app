import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/screens/invoice_status_screen.dart';
import 'package:waslapos_app/screens/wholesale_screen.dart';
import 'package:waslapos_app/screens/printer_settings_screen.dart';
import 'package:waslapos_app/screens/pos_shell.dart';
import 'package:waslapos_app/screens/pos_screen.dart';
import 'package:waslapos_app/screens/wholesale_receipt_screen.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/offline_store.dart';

/// Invoice actions live in the "إجراءات الفاتورة" menu.
Future<void> openMenu(WidgetTester tester, String item) async {
  await tester.ensureVisible(find.byTooltip('إجراءات الفاتورة'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('إجراءات الفاتورة'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const user = <String, dynamic>{
    'id': 1,
    'tenant_id': 1,
    'branch_id': 1,
    'name': 'Cashier',
  };
  const customer = <String, dynamic>{
    'id': 1,
    'name': 'عميل تجريبي',
    'current_balance': 100,
  };
  const product = <String, dynamic>{
    'id': 1,
    'name': 'صنف تجريبي',
    'price': 10,
    'cost_price': 3,
    'stock_quantity': 20,
    'min_wholesale_quantity': 1,
  };
  Map<String, dynamic>? submitted;
  String? submittedPath;
  Uri? invoiceRequest;
  double customerBalance = 100;
  bool replaySubmittedPayment = false;
  bool wrongPayment = false;
  http.Response reply(Object data, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json'},
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    submitted = null;
    submittedPath = null;
    invoiceRequest = null;
    customerBalance = 100;
    replaySubmittedPayment = false;
    wrongPayment = false;
    ApiClient.offline.value = false;
    ApiClient.sessionExpired.value = false;
    await ApiClient.saveSession(token: 'test', session: {'user': user});
    ApiClient.client = MockClient((request) async {
      if (request.method == 'PATCH') {
        submittedPath = request.url.path;
        submitted = jsonDecode(request.body);
        final amount = (submitted!['amount'] as num).toDouble();
        customerBalance = 110 - amount;
        return reply({
          'order': {
            'id': 8,
            'invoice_number': 'W-8',
            'customer_id': submitted!['customer_id'],
            'total': 10,
            'paid_amount': amount > 10 ? 10 : amount,
            'collected_amount': amount,
            'current_balance': customerBalance,
            'party': {...customer, 'current_balance': customerBalance},
          },
          'voucher': {
            'id': 9,
            'party_id': submitted!['customer_id'],
            'amount': amount,
            'payment_method': submitted!['payment_method'],
            'payment_date': submitted!['payment_date'],
            'notes': submitted!['notes'],
            'party': {...customer, 'current_balance': customerBalance},
            'current_balance': customerBalance,
          },
        });
      }
      if (request.method == 'POST') {
        submittedPath = request.url.path;
        submitted = jsonDecode(request.body);
        if (request.url.path.endsWith('/receipts')) {
          customerBalance -= (submitted!['amount'] as num).toDouble();
          return reply({
            'voucher': {
              'id': 7,
              'voucher_number': 'RCP-7',
              'amount': submitted!['amount'],
              'party': {...customer, 'current_balance': customerBalance},
              'previous_balance':
                  customerBalance + (submitted!['amount'] as num),
              'current_balance': customerBalance,
            },
          }, 201);
        }
        final received = wrongPayment
            ? 919
            : (submitted!['paid_amount'] as num).toDouble();
        return reply({
          'order': {
            'id': 8,
            'invoice_number': 'W-8',
            'total': 10,
            'paid_amount': received > 10 ? 10 : received,
            'collected_amount': received,
            'previous_balance': 100,
            'current_balance': 110 - received,
            'party': {...customer, 'current_balance': 110 - received},
            'items': [],
          },
        }, 201);
      }
      if (request.url.path.endsWith('/parties')) {
        return reply({
          'parties': [
            {...customer, 'current_balance': customerBalance},
            {
              'id': 2,
              'name': 'مورد تجريبي',
              'code': 'S00000001',
              'type': 'supplier',
              'current_balance': 50,
            },
          ],
        });
      }
      if (request.url.path.endsWith('/receipts')) {
        return reply({
          'voucher': {
            'id': 7,
            'party_id': 1,
            'voucher_number': 'RCP-7',
            'amount': 25,
            'payment_method': 'cash',
            'payment_date': '2026-11-08',
            'party': {...customer, 'current_balance': customerBalance},
            'previous_balance': customerBalance + 25,
            'current_balance': customerBalance,
          },
        });
      }
      if (request.url.path.endsWith('/sales/orders')) {
        return reply({
          'orders': {
            'data': [
              if (submittedPath?.endsWith('/pos/orders') == true)
                {'id': 8, 'invoice_number': 'W-8', 'total': 10, 'items': []},
            ],
            'last_page': 1,
          },
        });
      }
      if (request.url.path.endsWith('/invoice') ||
          request.url.path.endsWith('/pos/invoices')) {
        invoiceRequest = request.url;
        return reply({
          'order': {
            'id': 8,
            'invoice_number': 'W-8',
            'customer_id': 1,
            'total': 10,
            'paid_amount': replaySubmittedPayment
                ? (((submitted?['paid_amount']) as num?)?.clamp(0, 10))
                : 10,
            'collected_amount': replaySubmittedPayment
                ? (submitted?['paid_amount'])
                : 10,
            'linked_receipt': {
              'id': 9,
              'party_id': 1,
              'amount': replaySubmittedPayment
                  ? (submitted?['paid_amount'])
                  : 10,
              'payment_method': 'cash',
              'payment_date': '2026-11-08',
              'notes': 'سند الفاتورة',
              'party': {...customer, 'current_balance': customerBalance},
              'current_balance': customerBalance,
            },
            'items': [
              {
                'product_id': 1,
                'product': product,
                'quantity': 1,
                'unit_price': 10,
              },
            ],
          },
        });
      }
      return reply({
        'products': [product],
        'workspace_version': 1,
      });
    });
  });
  tearDown(() => ApiClient.client.close());

  for (final platform in [TargetPlatform.android]) {
    testWidgets('$platform starts at home and can close every department', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
      await tester.pumpAndSettle();
      expect(find.text('WaslaPOS'), findsOneWidget);
      expect(find.byType(WholesaleScreen), findsNothing);
      await tester.tap(find.text('فتح قسم'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
      // In the menu and among the home page sections.
      expect(find.text('التقارير'), findsNWidgets(2));
      expect(find.text('إعدادات الطابعات'), findsNothing);
      expect(find.text('قائمة الزيارات'), findsNothing);
      expect(find.text('سجل الفواتير'), findsNothing);
      await tester.tap(find.text('فاتورة مبيعات').last);
      await tester.pumpAndSettle();
      expect(find.byType(WholesaleScreen), findsOneWidget);
      expect(
        tester
            .widget<WholesaleScreen>(find.byType(WholesaleScreen))
            .salesInvoice,
        isTrue,
      );
      expect(find.byType(PosScreen), findsNothing);
      await tester.tap(find.byTooltip('إغلاق فاتورة مبيعات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.byType(WholesaleScreen), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق فاتورة مبيعات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إغلاق التبويب'));
      await tester.pumpAndSettle();
      expect(find.text('WaslaPOS'), findsOneWidget);
      await tester.tap(find.text('سند قبض مستقل'));
      await tester.pumpAndSettle();
      expect(find.byType(WholesaleReceiptScreen), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق سند قبض مستقل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إغلاق التبويب'));
      await tester.pumpAndSettle();
      expect(find.text('WaslaPOS'), findsOneWidget);
      await tester.tap(find.text('حالة الفواتير'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceStatusScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('Android keeps the printer settings out of its departments', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات الطابعات'), findsNothing);
    await tester.tap(find.text('فتح قسم'));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات الطابعات'), findsNothing);
    expect(find.byType(PrinterSettingsScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('Android starts wholesale and supplier can be selected by code', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاتورة مبيعات'));
    await tester.pumpAndSettle();
    expect(find.byType(WholesaleScreen), findsOneWidget);
    expect(find.byType(PosScreen), findsNothing);
    await tester.tap(find.text('عميل نقدي / عابر'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'بحث بالاسم أو الرمز أو الهاتف'),
      'S00000001',
    );
    await tester.pumpAndSettle();
    expect(find.text('عميل تجريبي'), findsNothing);
    await tester.tap(find.text('مورد تجريبي'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('صنف تجريبي').first);
    await tester.tap(find.text('صنف تجريبي').first);
    await tester.pumpAndSettle();
    if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.widgetWithText(TextField, 'المدفوع'));
    await tester.enterText(find.widgetWithText(TextField, 'المدفوع'), '0');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('حفظ الفاتورة'));
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pumpAndSettle();
    expect(submitted?['customer_id'], 2);
    expect(submittedPath, endsWith('/pos/orders'));
    expect(submitted?['total_amount'], 10);
    expect(submitted?['paid_amount'], 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('wholesale layout and save work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: WholesaleScreen(user: user)),
      );
      await tester.pumpAndSettle();
      final sections = [
        'wholesale-customer-section',
        'wholesale-products-section',
        'wholesale-cart-section',
        'wholesale-summary-section',
        'wholesale-payment-section',
      ];
      final positions = sections
          .map((key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy)
          .toList();
      for (var index = 1; index < positions.length; index++) {
        expect(positions[index], greaterThan(positions[index - 1]));
      }
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.tap(find.text('صنف تجريبي').first);
      await tester.pumpAndSettle();
      if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('حفظ'));
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
      }
      final discount = find.widgetWithText(TextField, 'الخصم');
      await tester.ensureVisible(discount);
      await tester.enterText(discount, '1');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(TextField, 'المدفوع'));
      await tester.enterText(find.widgetWithText(TextField, 'المدفوع'), '9');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('حفظ الفاتورة'));
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pumpAndSettle();
      expect(submitted?['items'][0]['price'], 10);
      expect(submittedPath, endsWith('/wholesale/orders'));
      expect(submitted?['paid_amount'], 9);
      expect(submitted?['discount_amount'], 1);
      expect(submitted?['operation_uuid'], isNotEmpty);
      expect(find.text('0 أصناف'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'customer payment preselects customer and preserves the wholesale cart',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WholesaleScreen(user: user)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.tap(find.text('صنف تجريبي').first);
      await tester.pumpAndSettle();
      if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('حفظ'));
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('عميل نقدي / عابر'));
      await tester.tap(find.text('عميل نقدي / عابر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل تجريبي').last);
      await tester.pumpAndSettle();
      await openMenu(tester, 'سند قبض مستقل');
      await tester.pumpAndSettle();
      expect(find.byType(WholesaleReceiptScreen), findsOneWidget);
      expect(find.text('عميل تجريبي'), findsWidgets);
      final amount = find.widgetWithText(TextField, 'المبلغ المقبوض');
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '25');
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(submitted?['customer_id'], 1);
      expect(submitted?['amount'], 25);
      expect(submitted?['payment_method'], 'cash');
      expect(submittedPath, endsWith('/wholesale/receipts'));
      // After saving, the screen is ready for a new receipt; the saved one opens from «آخر سند».
      expect(find.text('الرصيد بعد القبض: 75.00'), findsNothing);
      expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 أصناف'), findsOneWidget);
      expect(find.textContaining('75.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'invoice screen opens a standalone receipt without a selected customer',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WholesaleScreen(user: user, salesInvoice: true),
        ),
      );
      await tester.pumpAndSettle();

      await openMenu(tester, 'سند قبض مستقل');
      await tester.pumpAndSettle();

      expect(find.byType(WholesaleReceiptScreen), findsOneWidget);
      expect(find.text('سند قبض مستقل'), findsOneWidget);
      expect(find.text('عميل نقدي'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'رقم السند'), findsNothing);
    },
  );

  testWidgets('server payment mismatch is shown without resubmitting', (
    tester,
  ) async {
    wrongPayment = true;
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user, salesInvoice: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل نقدي / عابر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل تجريبي').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('صنف تجريبي').first);
    await tester.tap(find.text('صنف تجريبي').first);
    await tester.pumpAndSettle();
    if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('حفظ الفاتورة'));
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pumpAndSettle();
    expect(submitted?['paid_amount'], 0);
    expect(find.text('اختلاف في الدفعة المسجلة'), findsOneWidget);
    await tester.tap(find.text('فهمت'));
    await tester.pumpAndSettle();
    expect(find.text('0 أصناف'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final paid in [0, 5, 10]) {
    testWidgets('sales invoice preserves payment $paid when reopened', (
      tester,
    ) async {
      replaySubmittedPayment = true;
      await tester.pumpWidget(
        const MaterialApp(
          home: WholesaleScreen(user: user, salesInvoice: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل نقدي / عابر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل تجريبي').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.tap(find.text('صنف تجريبي').first);
      await tester.pumpAndSettle();
      if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('حفظ'));
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
      }
      final payment = find.widgetWithText(TextField, 'المدفوع');
      await tester.ensureVisible(payment);
      if (paid != 0) await tester.enterText(payment, '$paid');
      await tester.ensureVisible(find.text('حفظ الفاتورة'));
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pumpAndSettle();
      expect(submitted?['paid_amount'], paid);
      await openMenu(tester, 'آخر فاتورة');
      await tester.pumpAndSettle();
      expect(
        double.parse(tester.widget<TextField>(payment).controller!.text),
        paid,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('customer overpayment is sent and restored when reopening', (
    tester,
  ) async {
    replaySubmittedPayment = true;
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user, salesInvoice: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل نقدي / عابر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل تجريبي').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('صنف تجريبي').first);
    await tester.tap(find.text('صنف تجريبي').first);
    await tester.pumpAndSettle();
    if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
    }
    final payment = find.widgetWithText(TextField, 'المدفوع');
    await tester.ensureVisible(payment);
    await tester.enterText(payment, '15');
    await tester.pump();
    expect(
      find.text('الزيادة تسدد الرصيد أو تصبح رصيداً للعميل'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('حفظ الفاتورة'));
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pumpAndSettle();
    expect(submitted?['paid_amount'], 15);
    await openMenu(tester, 'آخر فاتورة');
    await tester.pumpAndSettle();
    expect(
      double.parse(tester.widget<TextField>(payment).controller!.text),
      15,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('sales invoices browse and edit through the sales API', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user, salesInvoice: true)),
    );
    await tester.pumpAndSettle();
    await openMenu(tester, 'آخر فاتورة');
    await tester.pumpAndSettle();
    expect(find.text('فاتورة W-8'), findsOneWidget);
    expect(invoiceRequest?.path, endsWith('/pos/invoices'));
    final save = find.widgetWithText(OutlinedButton, 'حفظ الفاتورة');
    expect(tester.widget<OutlinedButton>(save).onPressed, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('wholesale-price-1')))
          .enabled,
      isFalse,
    );
    await openMenu(tester, 'تعديل الفاتورة');
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('wholesale-price-1')))
          .enabled,
      isTrue,
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(submittedPath, endsWith('/pos/orders'));
    expect(submitted?['invoice_id'], 8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('linked invoice receipt is edited only from its dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user, salesInvoice: true)),
    );
    await tester.pumpAndSettle();
    await openMenu(tester, 'آخر فاتورة');
    await tester.pumpAndSettle();

    final invoicePayment = find.widgetWithText(TextField, 'المدفوع');
    await tester.ensureVisible(invoicePayment);
    expect(tester.widget<TextField>(invoicePayment).enabled, isFalse);
    await openMenu(tester, 'تعديل سند الفاتورة');
    await tester.pumpAndSettle();
    expect(find.text('تعديل سند الفاتورة'), findsOneWidget);

    final receiptAmount = find.widgetWithText(TextField, 'قيمة السند');
    await tester.enterText(receiptAmount, '15');
    await tester.tap(find.text('حفظ السند'));
    await tester.pumpAndSettle();

    expect(submittedPath, endsWith('/pos/invoices/8/receipt'));
    expect(submitted?['amount'], 15);
    expect(find.byType(AlertDialog), findsNothing);
    final save = find.widgetWithText(OutlinedButton, 'حفظ الفاتورة');
    expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('wholesale price and quantity are edited separately inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('صنف تجريبي').first);
    await tester.tap(find.text('صنف تجريبي').first);
    await tester.pumpAndSettle();
    if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
    }
    final price = find.byKey(const ValueKey('wholesale-price-1'));
    final quantity = find.byKey(const ValueKey('wholesale-quantity-1'));
    await tester.ensureVisible(price);
    await tester.enterText(price, '12.5');
    await tester.pumpAndSettle();
    await tester.enterText(quantity, '2.5');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('31.25'), findsWidgets);
    await tester.ensureVisible(find.widgetWithText(TextField, 'المدفوع'));
    await tester.enterText(find.widgetWithText(TextField, 'المدفوع'), '31.25');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('حفظ الفاتورة'));
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pumpAndSettle();
    expect(submitted?['items'][0]['price'], 12.5);
    expect(submitted?['items'][0]['quantity'], 2.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'invalid inline edits cannot save the previous valid cart values',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WholesaleScreen(user: user)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.ensureVisible(find.text('صنف تجريبي').first);
      await tester.tap(find.text('صنف تجريبي').first);
      await tester.pumpAndSettle();
      if (find.text('إضافة إلى الفاتورة').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('حفظ'));
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
      }
      final price = find.byKey(const ValueKey('wholesale-price-1'));
      await tester.ensureVisible(price);
      await tester.enterText(price, '');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('حفظ الفاتورة'));
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(price);
      await tester.enterText(price, '10');
      await tester.pumpAndSettle();
      final quantity = find.byKey(const ValueKey('wholesale-quantity-1'));
      await tester.enterText(quantity, '21');
      await tester.pumpAndSettle();
      expect(find.text('المتوفر 20'), findsOneWidget);
      await tester.ensureVisible(find.text('حفظ الفاتورة'));
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'receipt saves through durable checkout without displaying its server number',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WholesaleReceiptScreen(user: user, customers: [customer]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل نقدي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل تجريبي'));
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextField, 'المبلغ المقبوض');
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '25');
      await tester.ensureVisible(find.text('حفظ'));
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(submitted?['amount'], 25);
      expect(submitted?['payment_method'], 'cash');
      expect(submittedPath, endsWith('/wholesale/receipts'));
      // After saving, the screen is ready for a new receipt; the saved one opens from «آخر سند».
      expect(find.text('الرصيد بعد القبض: 75.00'), findsNothing);
      expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
      expect(submitted?['customer_id'], 1);
      expect(submitted?['operation_uuid'], isNotEmpty);
      expect(find.text('RCP-7'), findsNothing);
      await tester.ensureVisible(find.text('آخر سند'));
      await tester.tap(find.text('آخر سند'));
      await tester.pumpAndSettle();
      expect(find.text('الرصيد بعد القبض: 75.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standalone receipt loads customers without an invoice', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleReceiptScreen(user: user)),
    );
    await tester.pumpAndSettle();

    expect(find.text('سند قبض مستقل'), findsOneWidget);
    expect(
      find.text('سجّل قبضًا على حساب قديم للعميل دون ربطه بأي فاتورة.'),
      findsOneWidget,
    );
    await tester.tap(find.text('عميل نقدي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل تجريبي'));
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextField, 'المبلغ المقبوض');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '190');
    await tester.ensureVisible(find.text('حفظ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(submittedPath, endsWith('/wholesale/receipts'));
    expect(submitted?['customer_id'], 1);
    expect(submitted?['amount'], 190);
    expect(submitted?['receipt_id'], isNull);
  });
  testWidgets('confirmed checkout never resurrects its draft after a crash', (
    tester,
  ) async {
    final scope = '${ApiConfig.baseUrl}|1|1|1|wholesale';
    await OfflineStore('$scope-draft').saveDraft(1, {
      'draft_uuid': 'draft-1',
      'items': [
        {...product, 'quantity': 1},
      ],
    });
    await const FlutterSecureStorage().write(
      key: 'wasla_checkout_${Uri.encodeComponent(scope)}',
      value: jsonEncode({
        'status': 'confirmed',
        'payload': {'draft_uuid': 'draft-1'},
        'order': {'id': 8},
      }),
    );
    await tester.pumpWidget(
      const MaterialApp(home: WholesaleScreen(user: user)),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 أصناف'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'uncertain checkout preserves its draft and locks new financial writes',
    (tester) async {
      final scope = '${ApiConfig.baseUrl}|1|1|1|wholesale';
      await OfflineStore('$scope-draft').saveDraft(1, {
        'draft_uuid': 'draft-1',
        'items': [
          {...product, 'quantity': 1},
        ],
      });
      await const FlutterSecureStorage().write(
        key: 'wasla_checkout_${Uri.encodeComponent(scope)}',
        value: jsonEncode({
          'status': 'uncertain',
          'payload': {'draft_uuid': 'draft-1', 'operation_uuid': 'unknown'},
        }),
      );
      await tester.pumpWidget(
        const MaterialApp(home: WholesaleScreen(user: user)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 أصناف'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'حفظ الفاتورة'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
