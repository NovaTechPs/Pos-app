import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'bluetooth_printer_service.dart';

enum PrintRole {
  receipt('الفواتير الحرارية'),
  barcode('ملصقات الباركود'),
  report('التقارير وكشوف الحساب');

  const PrintRole(this.label);
  final String label;
}

typedef DirectPdfSender = Future<bool> Function(
  Printer printer,
  Uint8List bytes,
  PdfPageFormat format,
  String name,
  bool usePrinterSettings,
);

/// Device settings are independent of the signed-in account and server.
class PrinterRoutingService {
  PrinterRoutingService({
    this.storage = const FlutterSecureStorage(),
    Future<PrintingInfo> Function()? capabilities,
    Future<List<Printer>> Function()? printers,
    DirectPdfSender? send,
    bool? androidBluetooth,
    BluetoothPrinterService? bluetooth,
    this.discoveryCacheDuration = const Duration(seconds: 15),
  }) : capabilities = capabilities ?? Printing.info,
       printers = printers ?? Printing.listPrinters,
       _send = send ?? _direct,
       androidBluetooth =
           androidBluetooth ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       bluetooth = bluetooth ?? BluetoothPrinterService();

  static final instance = PrinterRoutingService();
  static const _key = 'wasla_device_printers_v1';
  final FlutterSecureStorage storage;
  final Future<PrintingInfo> Function() capabilities;
  final Future<List<Printer>> Function() printers;
  final DirectPdfSender _send;
  final bool androidBluetooth;
  final BluetoothPrinterService bluetooth;

  Future<PrintingInfo> settingsCapabilities() async => androidBluetooth
      ? const PrintingInfo(
          canPrint: true,
          directPrint: true,
          canListPrinters: true,
        )
      : capabilities();

  Future<List<Printer>> settingsPrinters() =>
      androidBluetooth ? bluetooth.printers() : printers();

  Future<int> paperWidth(PrintRole role) async =>
      int.tryParse(
            await storage.read(key: '${_key}_${role.name}_width') ?? '',
          ) ==
          576
      ? 576
      : 384;

  Future<void> setPaperWidth(PrintRole role, int width) => storage.write(
    key: '${_key}_${role.name}_width',
    value: '${width == 576 ? 576 : 384}',
  );
  final Duration discoveryCacheDuration;
  Future<PrintingInfo>? _infoFuture;
  Future<List<Printer>>? _printersFuture;
  Stopwatch _infoAge = Stopwatch();
  Stopwatch _printersAge = Stopwatch();

  Future<PrintingInfo> _printingInfo() async {
    if (_infoFuture == null || _infoAge.elapsed >= discoveryCacheDuration) {
      _infoAge = Stopwatch()..start();
      _infoFuture = capabilities();
    }
    final pending = _infoFuture!;
    try {
      return await pending;
    } catch (_) {
      if (identical(pending, _infoFuture)) _infoFuture = null;
      rethrow;
    }
  }

  Future<List<Printer>> _discoveredPrinters() async {
    if (_printersFuture == null ||
        _printersAge.elapsed >= discoveryCacheDuration) {
      _printersAge = Stopwatch()..start();
      _printersFuture = printers();
    }
    final pending = _printersFuture!;
    try {
      return await pending;
    } catch (_) {
      if (identical(pending, _printersFuture)) _printersFuture = null;
      rethrow;
    }
  }

  /// Discover devices while checkout is waiting for the server, without printing.
  Future<void> prepare(PrintRole role) async {
    if (androidBluetooth) return;
    final info = await _printingInfo();
    if (info.canPrint && info.directPrint) {
      await Future.wait<Object?>([selected(role), _discoveredPrinters()]);
    }
  }

  Future<Printer?> selected(PrintRole role) async {
    final raw = await storage.read(key: '${_key}_${role.name}');
    return raw == null ? null : Printer.fromMap(jsonDecode(raw) as Map);
  }

  Future<void> select(PrintRole role, Printer? printer) async {
    if (printer == null) {
      await storage.delete(key: '${_key}_${role.name}');
    } else {
      await storage.write(
        key: '${_key}_${role.name}',
        value: jsonEncode(printer.toMap()),
      );
    }
    _printersFuture = null;
  }

  static Future<bool> _direct(
    Printer printer,
    Uint8List bytes,
    PdfPageFormat format,
    String name,
    bool usePrinterSettings,
  ) async => await Printing.directPrintPdf(
    printer: printer,
    onLayout: (_) async => bytes,
    format: format,
    name: name,
    dynamicLayout: false,
    usePrinterSettings: usePrinterSettings,
  );

  Future<void> printPdf({
    required PrintRole role,
    required Uint8List bytes,
    required PdfPageFormat format,
    required String name,
  }) async {
    if (androidBluetooth) {
      final saved = await selected(role);
      if (saved == null ||
          !saved.url.startsWith(BluetoothPrinterService.prefix)) {
        throw StateError(
          'اختر طابعة بلوتوث ${role.label} من إعدادات الطابعات أولاً.',
        );
      }
      await bluetooth.printPdf(saved, bytes, await paperWidth(role));
      return;
    }
    final info = await _printingInfo();
    if (!info.canPrint) throw StateError('الطباعة غير متاحة على هذا الجهاز.');
    if (!info.directPrint) {
      // Mobile OS print services require their own system interface.
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: format,
        name: name,
      );
      return;
    }
    final discovery = await Future.wait<Object?>([
      selected(role),
      _discoveredPrinters(),
    ]);
    final saved = discovery[0] as Printer?;
    if (saved == null) {
      throw StateError(
        'اختر طابعة ${role.label} مرة واحدة من إعدادات الطابعات.',
      );
    }
    Printer? target;
    for (final printer in discovery[1] as List<Printer>) {
      if (printer.url == saved.url) target = printer;
    }
    if (target == null || !target.isAvailable) {
      _printersFuture = null;
      throw StateError(
        'الطابعة ${saved.name} غير متاحة. راجع اتصالها أو إعدادات الطابعات.',
      );
    }
    bool accepted;
    try {
      accepted = await _send(
        target,
        bytes,
        format,
        name,
        role != PrintRole.barcode,
      );
    } catch (_) {
      _printersFuture = null;
      rethrow;
    }
    if (!accepted) {
      _printersFuture = null;
      throw StateError(
        'لم تؤكد الطابعة قبول المهمة؛ تحقّق منها قبل إعادة الطباعة.',
      );
    }
  }
}
