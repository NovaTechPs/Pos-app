import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/widgets/customer_picker.dart';
import 'package:waslapos_app/widgets/popup_arrow_navigation.dart';
import 'package:waslapos_app/widgets/product_add_dialog.dart';

void main() {
  Widget app(Widget home, {bool autoFocus = true}) => MaterialApp(
    navigatorObservers: [PopupAutoFocusObserver(enabled: autoFocus)],
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: PopupArrowNavigation(child: child!),
    ),
    home: Scaffold(body: home),
  );

  bool focusedTile(WidgetTester tester, String title) {
    final tile = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<ListTile>();
    final text = tile?.title;
    return text is Text && text.data == title;
  }

  testWidgets(
    'arrows move from the search box through the list and Enter picks the item',
    (tester) async {
      String? picked;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TextField(autofocus: true),
                      for (final name in ['أول', 'ثاني', 'ثالث'])
                        ListTile(
                          title: Text(name),
                          onTap: () {
                            picked = name;
                            Navigator.pop(dialog);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc');

      // ←/→ stay in the text box for the caret.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedTile(tester, 'أول'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedTile(tester, 'ثاني'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedTile(tester, 'ثاني'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, 'ثاني');
    },
  );

  testWidgets('a popup opened without focus starts at its first item', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SimpleDialog(
                children: [
                  for (final name in ['أ', 'ب'])
                    ListTile(title: Text(name), onTap: () {}),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
        autoFocus: false,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedTile(tester, 'أ'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedTile(tester, 'ب'), isTrue);
  });

  const down = KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.arrowDown,
    logicalKey: LogicalKeyboardKey.arrowDown,
    timeStamp: Duration.zero,
  );

  testWidgets('arrows on main screens are left to the screen', (tester) async {
    await tester.pumpWidget(
      app(const Column(children: [TextField(autofocus: true), TextField()])),
    );
    await tester.pumpAndSettle();
    expect(PopupArrowNavigation.handle(down), KeyEventResult.ignored);
  });

  testWidgets('multi-line notes in a popup keep ↑/↓ for the caret', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(autofocus: true, maxLines: 3),
                    ListTile(title: Text('بعد')),
                  ],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(PopupArrowNavigation.handle(down), KeyEventResult.ignored);
  });

  testWidgets('the real customer picker is fully usable with arrows', (
    tester,
  ) async {
    int? selected = -1;
    await tester.pumpWidget(
      app(
        CustomerPicker(
          customers: const [
            {'id': 7, 'name': 'سعيد'},
            {'id': 8, 'name': 'منى'},
          ],
          value: null,
          onChanged: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.text('عميل نقدي'));
    await tester.pumpAndSettle();
    // Search box → "عميل نقدي" row → first customer → second customer.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 8);
  });

  Future<void> openDialog(WidgetTester tester, WidgetBuilder builder) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: builder),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Widget? focusedButtonLabel() => FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<TextButton>()
      ?.child;

  testWidgets('a confirmation opens focused on its first button (cancel)', (
    tester,
  ) async {
    var confirmed = false;
    await openDialog(
      tester,
      (dialog) => AlertDialog(
        title: const Text('تأكيد'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              confirmed = true;
              Navigator.pop(dialog);
            },
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
    final label = focusedButtonLabel();
    expect(label is Text ? label.data : null, 'إلغاء');
    // ← moves to the next button (RTL), Enter activates it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final next = focusedButtonLabel();
    expect(next is Text ? next.data : null, 'تأكيد الحذف');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('a popup with a text box opens ready to type', (tester) async {
    await openDialog(
      tester,
      (_) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('قبل'), onTap: null),
            TextField(key: Key('amount')),
          ],
        ),
      ),
    );
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>()
          ?.key,
      const Key('amount'),
    );
  });

  testWidgets('real popup: customer search keeps its own focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CustomerPicker(
          customers: const [
            {'id': 7, 'name': 'سعيد'},
          ],
          value: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('عميل نقدي'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>()
          ?.decoration
          ?.labelText,
      'بحث بالاسم أو الرمز أو الهاتف',
    );
  });

  testWidgets('real popup: add-product opens with a field focused', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openDialog(
      tester,
      (_) => const ProductAddDialog(
        product: {'id': 1, 'name': 'قهوة'},
        price: 10,
        loadHistory: null,
      ),
    );
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );
  });
}
