import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waslapos_app/screens/pos_screen.dart';
import 'package:waslapos_app/screens/pos_shell.dart';
import 'package:waslapos_app/screens/printer_settings_screen.dart';
import 'package:waslapos_app/widgets/pos_workspace.dart';
import 'package:waslapos_app/widgets/checkout_loading_overlay.dart';
import 'package:waslapos_app/screens/dashboard_screen.dart';
import 'package:waslapos_app/services/api_client.dart';
import 'package:waslapos_app/services/background_json.dart';
import 'package:waslapos_app/services/api_config.dart';
import 'package:waslapos_app/services/checkout_service.dart';
import 'package:waslapos_app/services/network_status.dart';

class TestNetworkStatus implements NetworkStatusSource {
  final controller = StreamController<bool>.broadcast();
  @override
  Future<bool> get available async => true;
  @override
  Stream<bool> get changes => controller.stream;
}

void testDesktopWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ApiClient.client.close());

  const user = <String, dynamic>{'id': 1, 'tenant_id': 1, 'branch_id': 1};
  http.Response response(Object data, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  void mockServer({
    void Function(Map<String, dynamic>)? onHold,
    bool lineContract = false,
    int catalogSize = 2,
    double? localStock,
    double? sharedStock,
    String Function()? catalogName,
    String Function()? customerName,
    void Function(http.Request)? onRequest,
    Future<http.Response> Function(Map<String, dynamic>)? onSale,
    Future<http.Response> Function(Map<String, dynamic>)? onBarcode,
    bool Function()? hasAddedBarcode,
    List<dynamic> Function()? heldOrders,
    Map<String, dynamic>? Function(http.Request)? savedInvoice,
  }) {
    ApiClient.client = MockClient((request) async {
      onRequest?.call(request);
      if (request.url.path.endsWith('/shifts/active')) {
        return response({
          'active_shift': {'id': 1, 'opening_cash': 0},
          'offline_contract_version': 1,
        });
      }
      if (request.url.path.endsWith('/theme')) {
        return response({'theme': 'blue'});
      }
      if (request.url.path.endsWith('/customers')) {
        return response({
          'customers': [
            {'id': 5, 'name': customerName?.call() ?? 'عميل مسجل'},
          ],
        });
      }
      if (request.url.path.endsWith('/pos/products')) {
        return response({
          if (lineContract) 'pos_line_contract_version': 2,
          'offline_contract_version': 1,
          'categories': [
            {
              'id': 1,
              'name': 'عام',
              'products': [
                {
                  'id': 1,
                  'stock_quantity': ?localStock,
                  'shared_stock_quantity': ?sharedStock,
                  'name': catalogName?.call() ?? 'قهوة',
                  'barcode': '00123',
                  if (hasAddedBarcode?.call() == true) 'barcodes': ['00AbC'],
                  'pricing_branch_id':
                      request.url.queryParameters['customer_id'] == '5' ? 2 : 1,
                  'branches': [
                    {
                      'id': request.url.queryParameters['customer_id'] == '5'
                          ? 2
                          : 1,
                      'pivot': {
                        'retail_price':
                            request.url.queryParameters['customer_id'] == '5'
                            ? '12.00'
                            : '10.00',
                      },
                    },
                  ],
                },
                {
                  'id': 2,
                  'name': 'صنف بلا سعر',
                  'barcode': '00999',
                  'branches': [],
                },
                for (var i = 3; i <= catalogSize; i++)
                  {
                    'id': i,
                    'name': 'صنف $i',
                    'barcode': 'ITEM$i',
                    'retail_price': 10,
                  },
              ],
            },
          ],
        });
      }
      if (request.url.path.endsWith('/pos/orders') && onSale != null) {
        return onSale(Map<String, dynamic>.from(jsonDecode(request.body)));
      }
      if (request.url.path.endsWith('/pos/product-barcodes') &&
          onBarcode != null) {
        return onBarcode(Map<String, dynamic>.from(jsonDecode(request.body)));
      }
      if (request.url.path.endsWith('/pos/held') && request.method == 'GET') {
        return response({'orders': heldOrders?.call() ?? []});
      }
      if (request.url.path.endsWith('/pos/held')) {
        final body = Map<String, dynamic>.from(jsonDecode(request.body));
        onHold?.call(body);
        return response({
          'message': 'تم التعليق',
          'order': {'id': 12, 'invoice_number': 'HOLD-12'},
        }, 201);
      }
      if (request.url.path.endsWith('/pos/invoices') && savedInvoice != null) {
        final order = savedInvoice(request);
        return order == null
            ? response({'message': 'لا توجد فاتورة'}, 404)
            : response({'order': order});
      }
      return response({'message': 'unexpected request'}, 500);
    });
  }

  Future<void> confirmHold(WidgetTester tester, {String? note}) async {
    expect(find.text('ملاحظة الفاتورة المعلقة'), findsOneWidget);
    if (note != null) {
      await tester.enterText(find.byKey(const Key('pos-hold-notes')), note);
    }
    await tester.tap(find.text('تعليق الفاتورة'));
    await tester.pumpAndSettle();
  }

  testDesktopWidgets(
    'shared stock is visible on product selection and cart remaining',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ApiClient.initialize();
      mockServer(localStock: 2, sharedStock: 12);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      expect(find.text('2 / 12'), findsWidgets);
      for (var index = 0; index < 3; index++) {
        await tester.tap(find.byKey(const ValueKey('pos-product-0')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('0 / 9'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testDesktopWidgets(
    'a 10000-product catalog stays lazy and repeated product taps never fetch data',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ApiClient.initialize();
      // The fake test clock never delivers background-isolate results.
      BackgroundJson.enabled = false;
      addTearDown(() => BackgroundJson.enabled = true);
      var requests = 0;
      mockServer(catalogSize: 10000, onRequest: (_) => requests++);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final initialRequests = requests;
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).products,
        hasLength(10000),
      );
      final cards = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith('pos-product-'),
      );
      expect(cards.evaluate().length, lessThan(80));
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const ValueKey('pos-product-0')));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['quantity'], 8);
      expect(requests, initialRequests);
      expect(cards.evaluate().length, lessThan(80));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testDesktopWidgets(
    'catalog search focuses while background requests are stalled',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ApiClient.initialize();
      ApiClient.offline.value = false;
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final server = ApiClient.client;
      final gate = Completer<void>();
      ApiClient.client = MockClient((request) async {
        await gate.future;
        return server.get(request.url, headers: request.headers);
      });
      await tester.tap(find.byKey(const Key('pos-tool-الأصناف')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pos-catalog-search')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(find.text('قهوة'), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      server.close();
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'gift picker adds a separate gift from an empty invoice and saves it with a paid duplicate',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? payload;
      mockServer(lineContract: true, onHold: (body) => payload = body);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة هدية'));
      await tester.pumpAndSettle();
      expect(find.text('اختر صنف الهدية — بدون مقابل'), findsOneWidget);
      await tester.tap(find.text('قهوة').last);
      await tester.pumpAndSettle();
      var workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['gift'], true);
      expect(workspace.total, 0);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.length, 2);
      expect(workspace.total, 10);
      workspace.onHold();
      await tester.pumpAndSettle();
      await confirmHold(tester);
      final items = payload!['items'] as List;
      expect(items[0]['is_gift'], true);
      expect(items[0]['price'], 0);
      expect(items[1]['is_gift'], false);
      expect(items[1]['price'], 10);
    },
  );

  testDesktopWidgets(
    'desktop arrows edit cart fields and select RTL products like the web',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer(lineContract: true);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-barcode-input')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      TextField field(int column) => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey('pos-cart-0-$column')),
          matching: find.byType(TextField),
        ),
      );
      expect(field(0).focusNode!.hasFocus, true);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('pos-cart-0-0')),
          matching: find.byType(TextField),
        ),
        '2.5',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(field(1).focusNode!.hasFocus, true);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('pos-cart-0-1')),
          matching: find.byType(TextField),
        ),
        '8',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(field(2).focusNode!.hasFocus, true);
      expect(tester.widget<PosWorkspace>(find.byType(PosWorkspace)).total, 20);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('pos-cart-0-2')),
          matching: find.byType(TextField),
        ),
        '25',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosWorkspace>(find.byType(PosWorkspace))
            .barcodeFocus
            .hasFocus,
        true,
      );
      expect(tester.widget<PosWorkspace>(find.byType(PosWorkspace)).total, 25);
      await tester.tap(find.byKey(const Key('pos-catalog-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosWorkspace>(find.byType(PosWorkspace))
            .cart
            .single['quantity'],
        3.5,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'barcode focus returns after picking a product, quantity buttons and removing a line',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer(lineContract: true);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-catalog-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      PosWorkspace workspace() =>
          tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace().barcodeFocus.hasFocus, true);
      expect(workspace().cart.length, 1);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.pumpAndSettle();
      expect(workspace().barcodeFocus.hasFocus, true);
      expect(workspace().cart.single['quantity'], 2);
      await tester.tap(find.byKey(const Key('pos-catalog-search')));
      workspace().onQuantity(0, 1);
      await tester.pumpAndSettle();
      expect(workspace().barcodeFocus.hasFocus, true);
      await tester.tap(find.byKey(const Key('pos-catalog-search')));
      workspace().onRemove(0);
      await tester.pumpAndSettle();
      expect(workspace().barcodeFocus.hasFocus, true);
      expect(workspace().cart, isEmpty);
    },
  );

  for (final keyboard in [false, true]) {
    testDesktopWidgets(
      'selecting a searched product clears search and restores all products keyboard=$keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        mockServer();
        await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
        await tester.pumpAndSettle();
        final search = find.byKey(const Key('pos-catalog-search'));
        // Desktop matches the web POS: all products, no category chips.
        await tester.enterText(search, 'قهوة');
        await tester.pump(const Duration(milliseconds: 120));
        expect(find.byKey(const ValueKey('pos-product-1')), findsNothing);
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.byKey(const ValueKey('pos-product-0')));
        }
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        expect(find.byKey(const ValueKey('pos-product-1')), findsOneWidget);
        final workspace = tester.widget<PosWorkspace>(
          find.byType(PosWorkspace),
        );
        expect(workspace.cart.single['quantity'], 1);
        expect(workspace.selectedCategoryId, isNull);
        expect(workspace.barcodeFocus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('pos-product-1')), findsOneWidget);
      },
    );
  }

  testDesktopWidgets(
    'desktop product search follows the web keys: Enter adds an exact code, Esc clears, offers filter',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer(catalogSize: 6);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      PosWorkspace workspace() =>
          tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      final search = find.byKey(const Key('pos-catalog-search'));
      expect(find.byKey(const Key('pos-product-table-header')), findsOneWidget);
      // Like the web POS, «عروض» shows only when a product has an offer.
      expect(find.text('عروض'), findsNothing);

      await tester.enterText(search, 'ITEM4');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(workspace().cart.single['product_id'], 4);
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(workspace().barcodeFocus.hasFocus, isTrue);

      await tester.enterText(search, 'صنف');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('pos-product-1')), findsOneWidget);

      // Web «سعر البيع — اختياري»: only products sold at that price.
      final price = find.byKey(const Key('pos-price-filter'));
      await tester.enterText(price, '987654');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد منتجات مطابقة'), findsOneWidget);
      final firstPrice = workspace().priceFor(workspace().products.first)!;
      await tester.enterText(price, firstPrice.toStringAsFixed(2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos-product-0')), findsOneWidget);
      await tester.enterText(price, '');
      await tester.tap(find.text('الكل'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos-product-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'desktop sidebar: collapsed icons, expands with labels, opens sections, arrows move',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const Key('desktop-sidebar'));
      expect(tester.getSize(sidebar).width, 64);
      expect(
        find.descendant(of: sidebar, matching: find.text('سجل الفواتير')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('sidebar-toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 224);
      expect(
        find.descendant(of: sidebar, matching: find.text('سجل الفواتير')),
        findsOneWidget,
      );

      // ↓ moves between sidebar items with the keyboard.
      Key? focusedItem() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<InkWell>()
          ?.key;
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byKey(const ValueKey('sidebar-نقطة البيع')),
                matching: find.byType(Row),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      expect(focusedItem(), const ValueKey('sidebar-نقطة البيع'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedItem(), const ValueKey('sidebar-مبيعات الجملة'));

      await tester.tap(find.byKey(const ValueKey('sidebar-إعدادات الطابعات')));
      // The printer screen keeps a spinner running while it looks for printers.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PrinterSettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'a saved invoice opens in the cart for viewing and unlocks with «تعديل»',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      Map<String, dynamic> invoice(int id, String type) => {
        'id': id,
        'invoice_number': 'A1-$id',
        'type': type,
        'editable_in_pos': type == 'pos',
        'created_at': '2026-11-17T19:20:27.000000Z',
        'customer_name': 'زبون عام',
        'total': 20,
        'discount': 0,
        'items': [
          {
            'product_id': 1,
            'quantity': 2,
            'unit_price': 10,
            'total_price': 20,
            'product': {'id': 1, 'name': 'قهوة'},
          },
        ],
      };
      mockServer(
        savedInvoice: (request) {
          requests.add(request.url);
          final before = request.url.queryParameters['before'];
          if (before == null) return invoice(60, 'pos');
          return before == '60' ? invoice(59, 'wholesale') : null;
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();

      var workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      workspace.actions['الفاتورة السابقة']!();
      await tester.pumpAndSettle();
      expect(requests.single.queryParameters['branch_id'], '1');
      expect(find.byKey(const Key('pos-viewed-invoice')), findsOneWidget);
      expect(find.textContaining('فاتورة محفوظة A1-60'), findsOneWidget);
      workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['quantity'], 2);
      expect(workspace.editingInvoiceId, isNull);

      // Locked: changing the quantity is refused until «تعديل».
      workspace.onQuantity(0, 1);
      await tester.pumpAndSettle();
      workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['quantity'], 2);

      // Older web/wholesale invoices come from the server too, but stay view-only here.
      await tester.tap(find.text('السابقة').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('فاتورة محفوظة A1-59'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-unlock-invoice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-viewed-invoice')), findsOneWidget);

      // Back to the POS invoice, «تعديل» unlocks it for editing.
      await tester.tap(find.text('التالية').last);
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['after'], '59');
      expect(find.textContaining('فاتورة محفوظة A1-60'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-unlock-invoice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-viewed-invoice')), findsNothing);
      workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.editingInvoiceId, 60);
      expect(workspace.cart.single['quantity'], 2);
    },
  );

  testWidgets(
    'a quick second tap on a product does not add its quantity twice',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final product = find.byKey(const ValueKey('pos-product-0'));
      await tester.tap(product);
      await tester.tap(product, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-product-quantity')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('add-product-quantity')),
        '6',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-product-quantity')), findsNothing);
      final cart = tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart;
      expect(cart.single['quantity'], 6);
    },
  );

  testWidgets('phones and narrow windows have no sidebar', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    mockServer();
    await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop-sidebar')), findsNothing);
  });

  testDesktopWidgets('the invoice table scrolls to each newly added line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    mockServer(catalogSize: 25);
    await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('pos-catalog-search'));
    final table = find.byKey(const Key('pos-invoice-lines'));
    for (var i = 3; i <= 22; i++) {
      await tester.enterText(search, 'ITEM$i');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final lines = tester
          .widget<PosWorkspace>(find.byType(PosWorkspace))
          .cart
          .length;
      final last = find.descendant(of: table, matching: find.text('صنف $i'));
      expect(last, findsOneWidget, reason: 'line ${lines - 1} is built');
      final view = tester.getRect(table);
      final row = tester.getRect(last);
      expect(row.top, greaterThanOrEqualTo(view.top - 1));
      expect(row.bottom, lessThanOrEqualTo(view.bottom + 1));
    }
    final scroll = tester.widget<ListView>(table).controller!;
    expect(scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testDesktopWidgets(
    'F4 cancellation preserves the cart and confirmation clears it without submitting a sale',
    (tester) async {
      var writes = 0;
      mockServer(
        onRequest: (request) {
          if (request.method == 'POST') writes++;
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        hasLength(1),
      );
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        hasLength(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      await tester.tap(find.text('إفراغ الفاتورة'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        isEmpty,
      );
      expect(writes, 0);
    },
  );

  for (final offline in [false, true]) {
    testDesktopWidgets(
      'held note is prompted, cancellation preserves the cart, and the list displays it offline=$offline',
      (tester) async {
        await ApiClient.saveSession(
          token: 'test-token',
          session: {'user': user},
        );
        final held = <dynamic>[];
        var writes = 0;
        mockServer(
          heldOrders: () => held,
          onHold: (body) {
            writes++;
            held.add({
              'id': 12,
              'invoice_number': 'HOLD-12',
              'notes': body['notes'],
              'total': 10,
              'items': body['items'],
            });
          },
        );
        await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
        await tester.pumpAndSettle();
        ApiClient.offline.value = offline;
        await tester.enterText(
          find.byKey(const Key('pos-barcode-input')),
          '00123',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('pos-hold-notes')),
          'ملاحظة ملغاة',
        );
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
          hasLength(1),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('pos-hold-notes')))
              .controller!
              .text,
          isEmpty,
        );
        await confirmHold(tester, note: 'طلب أحمد غداً');
        expect(writes, offline ? 0 : 1);
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
          isEmpty,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.textContaining('طلب أحمد غداً'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testDesktopWidgets(
    'line editor accepts fractional quantity and manual unit price',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer(lineContract: true);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onEditLine!(0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pos-line-quantity')), '٢٫٥');
      await tester.enterText(find.byKey(const Key('pos-line-price')), '٨');
      await tester.tap(find.text('تطبيق'));
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['quantity'], 2.5);
      expect(workspace.total, 20);
    },
  );

  testDesktopWidgets(
    'saved session opens offline and restores the unsubmitted invoice',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ApiClient.saveSession(
        token: 'cached-token',
        session: {'user': user},
      );
      mockServer(lineContract: true);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await ApiClient.initialize();
      ApiClient.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['product_id'], 1);
      expect(workspace.total, 10);
      expect(workspace.shiftId, 1);
      expect(ApiClient.offline.value, true);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'cached startup opens before a connected but stalled API responds',
    (tester) async {
      await ApiClient.saveSession(
        token: 'cached-token',
        session: {'user': user},
      );
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await ApiClient.initialize();
      expect(ApiClient.offline.value, false);
      final gate = Completer<http.Response>();
      ApiClient.client = MockClient((_) => gate.future);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.products.first['name'], 'قهوة');
      expect(workspace.shiftId, 1);
      expect(ApiClient.offline.value, true);
      gate.complete(response({'message': 'unavailable'}, 503));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'first startup reports which uncached data timed out without permitting sales',
    (tester) async {
      await ApiClient.initialize();
      await ApiClient.saveSession(token: 'new-token', session: {'user': user});
      final catalog = Completer<http.Response>();
      ApiClient.client = MockClient((request) async {
        if (request.url.path.endsWith('/pos/products')) return catalog.future;
        if (request.url.path.endsWith('/customers')) {
          return response({'customers': []});
        }
        return response({
          'active_shift': {'id': 1},
        });
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.byType(PosWorkspace), findsNothing);
      expect(find.textContaining('عند تحميل الأصناف'), findsOneWidget);
      expect(find.textContaining('لا تتوفر نسخة محلية'), findsOneWidget);
      expect(find.textContaining('Future not completed'), findsNothing);
      catalog.complete(response({'categories': []}));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'first device downloads automatically and resumes partial setup after a server failure',
    (tester) async {
      await ApiClient.initialize();
      await ApiClient.saveSession(
        token: 'device-token',
        session: {'user': user},
      );
      mockServer();
      final server = ApiClient.client;
      var reachable = false;
      var productReads = 0;
      var customerReads = 0;
      ApiClient.client = MockClient((request) async {
        if (request.url.path.endsWith('/pos/products')) productReads++;
        if (request.url.path.endsWith('/customers')) {
          customerReads++;
          if (!reachable) {
            return response({'message': 'temporarily unavailable'}, 503);
          }
        }
        return server.get(request.url, headers: request.headers);
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('سيُستأنف تنزيل البيانات تلقائياً'),
        findsOneWidget,
      );
      expect(productReads, 1);
      expect(customerReads, 1);
      expect(
        await ApiClient.offlineStore!.cached(
          Uri.parse('${ApiConfig.baseUrl}/pos/products?branch_id=1'),
        ),
        isNotNull,
      );
      reachable = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.products.first['name'], 'قهوة');
      expect(workspace.shiftId, 1);
      expect(customerReads, greaterThanOrEqualTo(2));
      expect(
        await ApiClient.offlineStore!.cached(
          Uri.parse('${ApiConfig.baseUrl}/customers'),
        ),
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      server.close();
      await ApiClient.initialize();
      ApiClient.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final restored = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(restored.products.first['name'], 'قهوة');
      expect(restored.shiftId, 1);
      expect(ApiClient.offline.value, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'download retries back off and stop when the screen is closed',
    (tester) async {
      await ApiClient.initialize();
      await ApiClient.saveSession(
        token: 'device-token',
        session: {'user': user},
      );
      var reads = 0;
      ApiClient.client = MockClient((_) async {
        reads++;
        return response({'message': 'temporarily unavailable'}, 503);
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      expect(reads, 3);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(reads, 6);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(reads, 6);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(reads, 9);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(reads, 9);
    },
  );

  testDesktopWidgets(
    'permanent permission errors do not trigger an automatic download loop',
    (tester) async {
      await ApiClient.initialize();
      await ApiClient.saveSession(
        token: 'device-token',
        session: {'user': user},
      );
      var reads = 0;
      ApiClient.client = MockClient((request) async {
        reads++;
        return response({'message': 'forbidden'}, 403);
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final initialReads = reads;
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(reads, initialReads);
      expect(
        find.textContaining('سيُستأنف تنزيل البيانات تلقائياً'),
        findsNothing,
      );
      expect(find.byType(PosWorkspace), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testDesktopWidgets(
    'online idle does not periodically download product or customer lists',
    (tester) async {
      var downloads = 0;
      mockServer(
        onRequest: (request) {
          if (request.url.path.endsWith('/pos/products') ||
              request.url.path.endsWith('/customers')) {
            downloads++;
          }
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final initialDownloads = downloads;
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(downloads, initialDownloads);
    },
  );

  testDesktopWidgets(
    'explicit refresh verifies the API even when the last connection state was offline',
    (tester) async {
      var updated = false;
      mockServer(catalogName: () => updated ? 'قهوة من الخادم' : 'قهوة');
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      updated = true;
      ApiClient.offline.value = true;
      tester
          .widget<PosWorkspace>(find.byType(PosWorkspace))
          .actions['تحديث الأصناف']!();
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.products.first['name'], 'قهوة من الخادم');
    },
  );

  testDesktopWidgets(
    'network restoration immediately syncs pending sales and refreshes master data',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final network = TestNetworkStatus();
      addTearDown(network.controller.close);
      await ApiClient.saveSession(
        token: 'cached-token',
        session: {'user': user},
      );
      var updated = false;
      var sales = 0;
      mockServer(
        lineContract: true,
        catalogName: () => updated ? 'قهوة جديدة' : 'قهوة',
        customerName: () => updated ? 'عميل محدث' : 'عميل مسجل',
        onSale: (_) async {
          sales++;
          return response({
            'order': {'id': 94},
          }, 201);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PosScreen(user: user, networkStatus: network),
        ),
      );
      await tester.pumpAndSettle();
      network.controller.add(false);
      await tester.pumpAndSettle();
      expect(ApiClient.offline.value, true);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onCheckout();
      await tester.pumpAndSettle();
      expect(sales, 0);
      updated = true;
      network.controller.add(true);
      await tester.pumpAndSettle();
      expect(sales, 1);
      expect(
        (await ApiClient.offlineStore!.operations()).single['status'],
        'confirmed',
      );
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.products.first['name'], 'قهوة جديدة');
      expect(workspace.customers.single['name'], 'عميل محدث');
      expect(ApiClient.offline.value, false);
    },
  );

  testDesktopWidgets(
    'reconnection automatically sends an unsent offline invoice only once',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ApiClient.saveSession(
        token: 'cached-token',
        session: {'user': user},
      );
      var sales = 0;
      mockServer(
        lineContract: true,
        onSale: (body) async {
          sales++;
          return response({
            'order': {'id': 88, 'invoice_number': 'INV-88', 'total': 10},
          }, 201);
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final connectedClient = ApiClient.client;
      ApiClient.client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      ApiClient.offline.value = true;
      tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onCheckout();
      await tester.pumpAndSettle();
      expect(sales, 0);
      expect(
        (await ApiClient.offlineStore!.operations()).single['status'],
        'queued',
      );
      ApiClient.client.close();
      ApiClient.client = connectedClient;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(sales, 1);
      expect(
        (await ApiClient.offlineStore!.operations()).single['status'],
        'confirmed',
      );
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(sales, 1);
    },
  );

  testDesktopWidgets(
    'automatic invoice sync works even when loading the product and customer lists fails',
    (tester) async {
      await ApiClient.saveSession(
        token: 'cached-token',
        session: {'user': user},
      );
      ApiClient.offline.value = true;
      final checkout = CheckoutService(
        scope: 'catalog-failure',
        offlineEndpoint: 'pos/orders',
      );
      await checkout.checkout(
        payload: {
          'branch_id': 1,
          'total_amount': 10,
          'items': [
            {'product_id': 1, 'price': 10, 'quantity': 1},
          ],
        },
        receiptItems: [
          {'product_id': 1, 'price': 10, 'quantity': 1},
        ],
        cashierName: 'cashier',
        offlineShiftId: 1,
      );
      var sales = 0;
      ApiClient.client = MockClient((request) async {
        if (request.method == 'POST') {
          sales++;
          return response({
            'order': {'id': 93},
          }, 201);
        }
        if (request.url.path.endsWith('/shifts/active')) {
          return response({
            'active_shift': {'id': 1},
          });
        }
        return response({'message': 'catalog unavailable'}, 503);
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(sales, 1);
      expect(
        (await ApiClient.offlineStore!.operations()).single['status'],
        'confirmed',
      );
    },
  );

  for (final held in [false, true]) {
    testDesktopWidgets(
      'desktop exposes recovery and restores clicks for unresolved ${held ? 'hold' : 'sale'}',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scope = '${ApiConfig.baseUrl}|1|1|1${held ? '|held' : ''}';
        final key = 'wasla_checkout_${Uri.encodeComponent(scope)}';
        FlutterSecureStorage.setMockInitialValues({
          key: jsonEncode({
            'status': 'sending',
            'created_at': '2026-10-29T06:00:00Z',
            'payload': {
              'operation_uuid': '12345678-1234-4234-8234-123456789012',
              'branch_id': 1,
              'total_amount': 10,
              'discount': 0,
              'payment_method': 'cash',
            },
            'items': [
              {
                'product_id': 1,
                'name': 'قهوة',
                'quantity': 1,
                'price': 10,
                'discount': 0,
              },
            ],
          }),
        });
        var sales = 0;
        mockServer(
          onSale: (_) async {
            sales++;
            return response({}, 500);
          },
        );
        await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pos-review-operation')), findsOneWidget);
        await tester.tap(find.byKey(const Key('pos-review-operation')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(
          find.text(held ? 'تحققت: محفوظة' : 'تحققت: الفاتورة محفوظة'),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pos-review-operation')), findsNothing);
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
        expect(
          sales,
          0,
          reason: 'review must never resubmit a financial operation',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final hold in [false, true]) {
    final scenario = hold ? 'held invoice' : 'sale';
    testDesktopWidgets(
      'duplicate display rows become one API item for $scenario',
      (tester) async {
        Map<String, dynamic>? submitted;
        mockServer(
          onHold: (body) => submitted = body,
          onSale: (body) async {
            submitted = body;
            return response({
              'order': {'id': 1, 'invoice_number': 'SALE-1'},
            }, 201);
          },
        );
        await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
        await tester.pumpAndSettle();
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onMergeSimilar!(
          false,
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.enterText(
            find.byKey(const Key('pos-barcode-input')),
            '00123',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart.length,
          2,
        );
        await tester.sendKeyEvent(
          hold ? LogicalKeyboardKey.f2 : LogicalKeyboardKey.f3,
        );
        await tester.pumpAndSettle();
        if (hold) await confirmHold(tester);
        final lines = submitted!['items'] as List;
        expect(lines.length, 1);
        expect(lines.single['product_id'], 1);
        expect(lines.single['quantity'], 2);
        expect(lines.single['price'], 10);
        expect(submitted!['total_amount'], 20);
        expect(
          tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testDesktopWidgets(
    'F keys match toolbar actions and cannot act behind a dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var holds = 0;
      var sales = 0;
      var heldReads = 0;
      mockServer(
        onHold: (_) => holds++,
        onRequest: (request) {
          if (request.url.path.endsWith('/pos/orders')) sales++;
          if (request.url.path.endsWith('/pos/held') &&
              request.method == 'GET') {
            heldReads++;
          }
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      expect(find.text('تأكيد إفراغ الفاتورة'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(sales, 0);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await confirmHold(tester);
      expect(holds, 1);
      expect(sales, 0);
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(heldReads, 1);
      expect(find.text('لا توجد فواتير معلقة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'inactive POS tab ignores F keys and F10 works after returning from another tab',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var holds = 0;
      mockServer(onHold: (_) => holds++);
      await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await PosShell.open(
        tester.element(find.byType(PosScreen)),
        'اختبار الاختصارات',
        const Scaffold(body: TextField()),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(holds, 0);
      await tester.tap(find.text('نقطة البيع').last);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pos-catalog-search')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      await confirmHold(tester);
      expect(holds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'unknown barcodes open the choice dialog without searching and valid barcodes still add once',
    (tester) async {
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pos-barcode-input')), 'ق');
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).products.length,
        2,
      );
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        'قهوة',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).products.length,
        2,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('⚠ الباركود غير موجود'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        isEmpty,
      );
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosWorkspace>(find.byType(PosWorkspace))
            .barcodeFocus
            .hasFocus,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart.length,
        1,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.products.length, 2);
      expect(workspace.cart.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'linking a missing barcode preserves the invoice and makes the alias immediately scannable',
    (tester) async {
      var linked = false;
      var sales = 0;
      mockServer(
        hasAddedBarcode: () => linked,
        onRequest: (request) {
          if (request.url.path.endsWith('/pos/orders')) sales++;
        },
        onBarcode: (body) async {
          expect(body['barcode'], '00AbC');
          expect(body['product_id'], 1);
          linked = true;
          return response({
            'product': {
              'id': 1,
              'name': 'قهوة',
              'barcodes': ['00AbC'],
              'branches': [
                {
                  'id': 1,
                  'pivot': {'retail_price': 10, 'stock_quantity': 9},
                },
              ],
            },
          });
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00AbC',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(sales, 0);
      expect(
        tester
            .widget<PosWorkspace>(find.byType(PosWorkspace))
            .cart
            .single['quantity'],
        1,
      );
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'بحث عن صنف موجود'),
        'قهوة',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(ListTile, 'قهوة'),
        ),
      );
      await tester.pumpAndSettle();
      expect(linked, isTrue);
      expect(find.byType(Dialog), findsNothing);
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      expect(workspace.cart.single['quantity'], 1);
      expect(workspace.barcodeFocus.hasFocus, isTrue);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00AbC',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PosWorkspace>(find.byType(PosWorkspace))
            .cart
            .single['quantity'],
        2,
      );
      expect(sales, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'confirmed save immediately accepts the next invoice without catalog reload or printing',
    (tester) async {
      final firstSale = Completer<http.Response>();
      final saved = <Map<String, dynamic>>[];
      var reads = 0;
      var shiftChecks = 0;
      var prints = 0;
      const channel = MethodChannel('net.nfet.printing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            prints++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      mockServer(
        onRequest: (request) {
          if (request.method == 'GET') {
            if (request.url.path.endsWith('/shifts/active')) {
              shiftChecks++;
            } else {
              reads++;
            }
          }
        },
        onSale: (body) async {
          saved.add(body);
          if (saved.length == 1) return firstSale.future;
          return response({
            'order': {'id': saved.length, 'invoice_number': 'SALE-2'},
          }, 201);
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      final initialReads = reads;
      final initialShiftChecks = shiftChecks;
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final workspace = tester.widget<PosWorkspace>(find.byType(PosWorkspace));
      workspace.onCheckout();
      workspace.onCheckout();
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved.length, 1);
      expect(find.byType(CheckoutLoadingOverlay), findsOneWidget);
      expect(find.text('جارٍ حفظ الفاتورة…'), findsOneWidget);
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart.length,
        1,
      );
      firstSale.complete(
        response({
          'order': {'id': 1, 'invoice_number': 'SALE-1'},
        }, 201),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutLoadingOverlay), findsNothing);
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        isEmpty,
      );
      expect(reads, initialReads);
      expect(prints, 0);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onCheckout();
      await tester.pumpAndSettle();
      expect(saved.length, 2);
      expect(shiftChecks, initialShiftChecks);
      expect(saved[0]['operation_uuid'], isNot(saved[1]['operation_uuid']));
      expect(reads, initialReads);
      expect(prints, 0);
      expect(
        tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'POS startup loads independent data concurrently and still waits for the active shift',
    (tester) async {
      final shift = Completer<http.Response>();
      final requests = <String>{};
      ApiClient.client = MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/shifts/active')) return shift.future;
        if (request.url.path.endsWith('/pos/products')) {
          return response({'categories': []});
        }
        if (request.url.path.endsWith('/customers')) {
          return response({'customers': []});
        }
        return response({'message': 'unexpected request'}, 500);
      });
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(requests.any((path) => path.endsWith('/shifts/active')), isTrue);
      expect(requests.any((path) => path.endsWith('/pos/products')), isTrue);
      expect(requests.any((path) => path.endsWith('/customers')), isTrue);
      expect(find.byKey(const Key('pos-barcode-input')), findsNothing);
      shift.complete(
        response({
          'active_shift': {'id': 1, 'opening_cash': 0},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-barcode-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'mixed gift and paid duplicate is rejected without changing the cart or submitting',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? held;
      mockServer(onHold: (body) => held = body);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة هدية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('قهوة').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      tester.widget<PosWorkspace>(find.byType(PosWorkspace)).onHold();
      await tester.pumpAndSettle();
      expect(held, isNull);
      expect(find.textContaining('الصنف مكرر بأسعار مختلفة'), findsOneWidget);
      final lines = tester.widget<PosWorkspace>(find.byType(PosWorkspace)).cart;
      expect(lines.length, 2);
      expect(lines.first['discount'], 0);
      expect(lines.last['discount'], 10);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets('cash tender below total blocks keyboard checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var checkoutCalls = 0;
    mockServer(
      onRequest: (request) {
        if (request.method == 'POST' &&
            !request.url.path.endsWith('/pos/held')) {
          checkoutCalls++;
        }
      },
    );
    await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pos-barcode-input')), '00123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pos-paid-input')), '5');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(checkoutCalls, 0);
    expect(find.textContaining('النقد المستلم غير صالح'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testDesktopWidgets(
    'department tabs retain forms, reuse tabs and return to POS on close',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosShell(user: user)));
      await tester.pumpAndSettle();
      final posContext = tester.element(find.byType(PosScreen));
      await PosShell.open(
        posContext,
        'قسم تجريبي',
        const Scaffold(body: TextField(key: Key('tab-form'))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tab-form')),
        'بيانات محفوظة',
      );
      await tester.tap(find.text('نقطة البيع').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-barcode-input')), findsOneWidget);
      await PosShell.open(posContext, 'قسم تجريبي', const SizedBox());
      await tester.pumpAndSettle();
      expect(find.text('قسم تجريبي'), findsOneWidget);
      expect(find.text('بيانات محفوظة'), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق قسم تجريبي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إغلاق التبويب'));
      await tester.pumpAndSettle();
      expect(find.text('قسم تجريبي'), findsNothing);
      expect(find.byKey(const Key('pos-barcode-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testDesktopWidgets(
    'external scanner adds the product and cash checkout never picks the first customer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? held;
      mockServer(onHold: (body) => held = body);
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PosScreen(user: user),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تعليق الفاتورة'));
      await tester.pumpAndSettle();
      await confirmHold(tester);
      expect(held, isNotNull);
      expect(held?['customer_id'], isNull);
      expect(held?['subtotal'], 10);
      expect((held?['items'] as List).single['price'], 10);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'a missing catalog price is rejected instead of using a fallback',
    (tester) async {
      mockServer();
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00999',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('لا يوجد سعر معتمد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'dashboard failures show a retry and never display zero sales as real data',
    (tester) async {
      ApiClient.client = MockClient(
        (_) async => response({'message': 'offline'}, 503),
      );
      await tester.pumpWidget(
        const MaterialApp(home: DashboardScreen(user: user)),
      );
      await tester.pumpAndSettle();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.text('0 فواتير'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'keyboard checkout cannot bypass an invalid discount field',
    (tester) async {
      int orders = 0;
      mockServer(
        onRequest: (request) {
          if (request.url.path.endsWith('/pos/orders')) orders++;
        },
      );
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('السلة (1)'));
      await tester.pumpAndSettle();
      final discount = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'خصم الفاتورة',
      );
      await tester.enterText(discount, '-1');
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(orders, 0);
      expect(find.text('صحح خصم الفاتورة أولاً.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testDesktopWidgets(
    'changing the customer reprices existing cart lines before saving',
    (tester) async {
      Map<String, dynamic>? held;
      mockServer(onHold: (body) => held = body);
      await tester.pumpWidget(const MaterialApp(home: PosScreen(user: user)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-barcode-input')),
        '00123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل نقدي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل مسجل').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تعليق الفاتورة'));
      await tester.pumpAndSettle();
      await confirmHold(tester);
      expect(held?['customer_id'], 5);
      expect(held?['subtotal'], 12);
      expect((held?['items'] as List).single['price'], 12);
      expect(tester.takeException(), isNull);
    },
  );
}
