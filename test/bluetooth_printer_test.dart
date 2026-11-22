import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:waslapos_app/services/bluetooth_printer_service.dart';
import 'package:waslapos_app/services/printer_routing_service.dart';
import 'package:waslapos_app/screens/printer_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'builtInAvailable') return false;
          if (call.method == 'pairedDevices') {
            return [
              {'name': 'Thermal', 'address': 'AA:BB:CC:DD:EE:FF'},
            ];
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, null);
  });

  testWidgets(
    'mobile settings allow selecting and keeping a Bluetooth receipt printer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PrinterRoutingService(androidBluetooth: true);
      await tester.pumpWidget(
        MaterialApp(home: PrinterSettingsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thermal (Bluetooth)').last);
      await tester.pumpAndSettle();
      expect(
        (await service.selected(PrintRole.receipt))!.url,
        'bluetooth:AA:BB:CC:DD:EE:FF',
      );
      expect(await service.selected(PrintRole.barcode), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Android saves separate roles and sends PDF directly with stored width',
    () async {
      final service = PrinterRoutingService(
        androidBluetooth: true,
        capabilities: () =>
            throw StateError('System printing must not be used'),
        printers: () => throw StateError('System discovery must not be used'),
      );
      final devices = await service.settingsPrinters();
      await service.select(PrintRole.receipt, devices.single);
      await service.setPaperWidth(PrintRole.receipt, 576);
      await service.prepare(PrintRole.receipt);
      expect(await service.selected(PrintRole.barcode), isNull);
      await service.printPdf(
        role: PrintRole.receipt,
        bytes: Uint8List.fromList([1, 2, 3]),
        format: PdfPageFormat.roll80,
        name: 'receipt',
      );
      expect(calls.map((c) => c.method), [
        'builtInAvailable',
        'pairedDevices',
        'printPdf',
      ]);
      expect(calls.last.arguments['address'], 'AA:BB:CC:DD:EE:FF');
      expect(calls.last.arguments['width'], 576);
      expect(calls.last.arguments['bytes'], [1, 2, 3]);
    },
  );

  test('without a chosen printer the first print uses the paired printer and remembers it', () async {
    final service = PrinterRoutingService(androidBluetooth: true);
    await service.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List.fromList([1]),
      format: PdfPageFormat.roll57,
      name: 'receipt',
    );
    expect(calls.last.method, 'printPdf');
    expect(calls.last.arguments['address'], 'AA:BB:CC:DD:EE:FF');
    expect(
      (await service.selected(PrintRole.receipt))!.url,
      'bluetooth:AA:BB:CC:DD:EE:FF',
    );
  });

  test('among several paired devices the one named like a printer is used, otherwise nothing prints', () async {
    var paired = [
      {'name': 'Galaxy Buds', 'address': '11:11:11:11:11:11'},
      {'name': 'MPT-II', 'address': '22:22:22:22:22:22'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'builtInAvailable') return false;
          if (call.method == 'pairedDevices') return paired;
          return null;
        });
    final service = PrinterRoutingService(androidBluetooth: true);
    Future<void> print() => service.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List(1),
      format: PdfPageFormat.roll57,
      name: 'receipt',
    );
    await print();
    expect(calls.last.arguments['address'], '22:22:22:22:22:22');

    await service.select(PrintRole.receipt, null);
    paired = [
      {'name': 'Galaxy Buds', 'address': '11:11:11:11:11:11'},
      {'name': 'Car Audio', 'address': '33:33:33:33:33:33'},
    ];
    calls.clear();
    await expectLater(print(), throwsStateError);
    expect(calls.map((call) => call.method), isNot(contains('printPdf')));
  });

  test('a remembered printer that was unpaired is replaced by the printer paired now', () async {
    final printed = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, (
          call,
        ) async {
          if (call.method == 'builtInAvailable') return false;
          if (call.method == 'pairedDevices') {
            return [
              {'name': 'New Printer', 'address': '99:99:99:99:99:99'},
            ];
          }
          final address = (call.arguments as Map)['address'] as String;
          if (address != '99:99:99:99:99:99') {
            throw PlatformException(
              code: 'bluetooth_print',
              message:
                  'الطابعة غير مقترنة. اقترن بها من إعدادات بلوتوث الجهاز.',
            );
          }
          printed.add(address);
          return null;
        });
    final service = PrinterRoutingService(androidBluetooth: true);
    await service.select(
      PrintRole.receipt,
      const Printer(url: 'bluetooth:AA:BB:CC:DD:EE:FF', name: 'Old'),
    );
    await service.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List(1),
      format: PdfPageFormat.roll57,
      name: 'receipt',
    );
    expect(printed, ['99:99:99:99:99:99']);
    expect(
      (await service.selected(PrintRole.receipt))!.url,
      'bluetooth:99:99:99:99:99:99',
    );
  });

  test(
    'connection failure propagates once without retry or system fallback',
    () async {
      final service = PrinterRoutingService(androidBluetooth: true);
      final device = (await service.settingsPrinters()).single;
      await service.select(PrintRole.receipt, device);
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BluetoothPrinterService.channel, (
            call,
          ) async {
            attempts++;
            throw PlatformException(
              code: 'bluetooth_print',
              message: 'Disconnected',
            );
          });
      await expectLater(
        service.printPdf(
          role: PrintRole.receipt,
          bytes: Uint8List(1),
          format: PdfPageFormat.roll57,
          name: 'receipt',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(attempts, 1);
    },
  );

  test('Q6 built-in printer remains available with Bluetooth off and uses its service', () async {
    final methods = <String>[];
    Map<dynamic, dynamic>? payload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, (
          call,
        ) async {
          methods.add(call.method);
          if (call.method == 'builtInAvailable') return true;
          if (call.method == 'pairedDevices') {
            throw PlatformException(code: 'off');
          }
          payload = call.arguments as Map;
          return null;
        });
    final service = PrinterRoutingService(androidBluetooth: true);
    final device = (await service.settingsPrinters()).single;
    await service.select(PrintRole.receipt, device);
    await service.setPaperWidth(PrintRole.receipt, 576);
    await service.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List(1),
      format: PdfPageFormat.roll57,
      name: 'Q6 receipt',
    );
    expect(methods, ['builtInAvailable', 'pairedDevices', 'printBuiltIn']);
    expect(payload!['width'], 384);
  });
}
