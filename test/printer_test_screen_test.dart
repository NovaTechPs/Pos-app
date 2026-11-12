import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:waslapos_app/screens/printer_test_screen.dart';
import 'package:waslapos_app/services/printer_routing_service.dart';
import 'package:waslapos_app/services/printer_test_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final path = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (!path.startsWith('assets/fonts/')) return null;
          return ByteData.sublistView(await File(path).readAsBytes());
        });
  });

  test(
    'Arabic test documents build offline at both supported paper widths',
    () async {
      for (final width in [384, 576]) {
        final bytes = await PrinterTestDocument.build(
          width,
          printedAt: DateTime(2026, 11, 1, 12, 30),
        );
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(1000));
        expect(PrinterTestDocument.format(width).width, greaterThan(0));
      }
      expect(
        PrinterTestDocument.format(384).width,
        lessThan(PrinterTestDocument.format(576).width),
      );
    },
  );

  testWidgets('missing printer is explained without submitting a print job', (
    tester,
  ) async {
    final service = PrinterRoutingService(androidBluetooth: false);
    await tester.pumpWidget(
      MaterialApp(home: PrinterTestScreen(service: service)),
    );
    await tester.tap(find.text('طباعة صفحة اختبار'));
    await tester.pumpAndSettle();
    expect(find.textContaining('اختر طابعة الفواتير الحرارية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test button sends one sample PDF to the saved receipt printer', (
    tester,
  ) async {
    const printer = Printer(url: 'thermal-test', name: 'Test Printer');
    var sent = 0;
    final service = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: () async =>
          const PrintingInfo(canPrint: true, directPrint: true),
      printers: () async => [printer],
      send: (target, bytes, format, name, settings) async {
        expect(target.url, printer.url);
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(name, 'WaslaPOS Printer Test');
        sent++;
        return true;
      },
    );
    await service.select(PrintRole.receipt, printer);
    await tester.pumpWidget(
      MaterialApp(
        home: PrinterTestScreen(
          service: service,
          document: (_) async => Uint8List.fromList(utf8.encode('%PDF-sample')),
        ),
      ),
    );
    await tester.tap(find.text('طباعة صفحة اختبار'));
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(
      find.textContaining('تم إرسال صفحة الاختبار إلى Test Printer'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
