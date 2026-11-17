import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:waslapos_app/screens/printer_settings_screen.dart';
import 'package:waslapos_app/services/printer_routing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const thermal = Printer(url: 'thermal-usb', name: 'BTP-R880NP');
  const labels = Printer(url: 'labels-usb', name: 'Label Printer');
  const report = Printer(url: 'a4-network', name: 'Office A4');
  Future<PrintingInfo> info() async => const PrintingInfo(
    canPrint: true,
    directPrint: true,
    canListPrinters: true,
  );

  test('preparing overlaps discovery, shares it with printing and never sends a job', () async {
    var scans = 0;
    var capabilityReads = 0;
    final jobs = <String>[];
    final devices = Completer<List<Printer>>();
    final routing = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: () async {
        capabilityReads++;
        return info();
      },
      printers: () {
        scans++;
        return devices.future;
      },
      send: (printer, _, _, _, _) async {
        jobs.add(printer.url);
        return true;
      },
    );
    await routing.select(PrintRole.receipt, thermal);
    final preparing = routing.prepare(PrintRole.receipt);
    await Future<void>.delayed(Duration.zero);
    expect(scans, 1);
    expect(jobs, isEmpty);
    Future<void> print() => routing.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List(0),
      format: PdfPageFormat.a4,
      name: 'receipt',
    );
    final printing = print();
    devices.complete([thermal, report]);
    await Future.wait([preparing, printing]);
    await print();
    expect(scans, 1);
    expect(capabilityReads, 1);
    expect(jobs, [thermal.url, thermal.url]);
    await routing.select(PrintRole.receipt, report);
    await print();
    expect(scans, 2);
    expect(jobs.last, report.url);
  });

  test(
    'failed jobs invalidate discovery and never retry a financial receipt',
    () async {
      var scans = 0;
      var jobs = 0;
      final routing = PrinterRoutingService(
        androidBluetooth: false,
        capabilities: info,
        printers: () async {
          scans++;
          return [thermal];
        },
        send: (_, _, _, _, _) async {
          jobs++;
          return jobs > 1;
        },
      );
      await routing.select(PrintRole.receipt, thermal);
      Future<void> print() => routing.printPdf(
        role: PrintRole.receipt,
        bytes: Uint8List(0),
        format: PdfPageFormat.a4,
        name: 'receipt',
      );
      await expectLater(print(), throwsStateError);
      expect(jobs, 1);
      await print();
      expect(scans, 2);
      expect(jobs, 2);
    },
  );

  test(
    'expired discovery detects a disconnected printer without redirecting',
    () async {
      var connected = true;
      var jobs = 0;
      final routing = PrinterRoutingService(
        androidBluetooth: false,
        discoveryCacheDuration: Duration.zero,
        capabilities: info,
        printers: () async => connected ? [thermal] : [report],
        send: (_, _, _, _, _) async {
          jobs++;
          return true;
        },
      );
      await routing.select(PrintRole.receipt, thermal);
      await routing.prepare(PrintRole.receipt);
      connected = false;
      await expectLater(
        routing.printPdf(
          role: PrintRole.receipt,
          bytes: Uint8List(0),
          format: PdfPageFormat.a4,
          name: 'receipt',
        ),
        throwsStateError,
      );
      expect(jobs, 0);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'settings save a thermal device independently at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final routing = PrinterRoutingService(
          androidBluetooth: false,
          capabilities: info,
          printers: () async => [thermal, labels, report],
        );
        await tester.pumpWidget(
          MaterialApp(home: PrinterSettingsScreen(service: routing)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('receipt-null')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(thermal.name).last);
        await tester.pumpAndSettle();
        expect((await routing.selected(PrintRole.receipt))!.url, thermal.url);
        expect(await routing.selected(PrintRole.barcode), isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('device routes persist independently and send each document directly to its own printer', () async {
    final jobs = <String>[];
    final routing = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: info,
      printers: () async => [thermal, labels, report],
      send: (printer, bytes, format, name, useSettings) async {
        jobs.add(printer.url);
        expect(bytes, [37, 80, 68, 70]);
        expect(useSettings, isTrue);
        return true;
      },
    );
    await Future.wait([
      routing.select(PrintRole.receipt, thermal),
      routing.select(PrintRole.barcode, labels),
      routing.select(PrintRole.report, report),
    ]);
    final restarted = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: info,
      printers: routing.printers,
      send: (printer, bytes, format, name, useSettings) async {
        jobs.add(printer.url);
        return true;
      },
    );
    for (final role in PrintRole.values) {
      expect(
        (await restarted.selected(role))!.url,
        [thermal, labels, report][role.index].url,
      );
      await routing.printPdf(
        role: role,
        bytes: Uint8List.fromList([37, 80, 68, 70]),
        format: PdfPageFormat.a4,
        name: role.name,
      );
    }
    expect(jobs, [thermal.url, labels.url, report.url]);
    await restarted.select(PrintRole.barcode, null);
    expect(await restarted.selected(PrintRole.barcode), isNull);
    expect((await restarted.selected(PrintRole.receipt))!.url, thermal.url);
  });

  test('missing or removed printer never falls back to another device or a print dialog', () async {
    var jobs = 0;
    final routing = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: info,
      printers: () async => [report],
      send: (_, _, _, _, _) async {
        jobs++;
        return true;
      },
    );
    Future<void> print() => routing.printPdf(
      role: PrintRole.receipt,
      bytes: Uint8List(0),
      format: PdfPageFormat.a4,
      name: 'receipt',
    );
    await expectLater(
      print(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('إعدادات الطابعات'),
        ),
      ),
    );
    await routing.select(PrintRole.receipt, thermal);
    await expectLater(
      print(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('غير متاحة'),
        ),
      ),
    );
    expect(jobs, 0);
  });

  test('a rejected print job is not retried or redirected', () async {
    var jobs = 0;
    final routing = PrinterRoutingService(
      androidBluetooth: false,
      capabilities: info,
      printers: () async => [thermal],
      send: (_, _, _, _, _) async {
        jobs++;
        return false;
      },
    );
    await routing.select(PrintRole.receipt, thermal);
    await expectLater(
      routing.printPdf(
        role: PrintRole.receipt,
        bytes: Uint8List(0),
        format: PdfPageFormat.a4,
        name: 'receipt',
      ),
      throwsStateError,
    );
    expect(jobs, 1);
  });
}
