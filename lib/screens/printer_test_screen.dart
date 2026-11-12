import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_printer_service.dart';
import '../services/printer_routing_service.dart';
import '../services/printer_test_document.dart';

class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key, this.service, this.document});
  final PrinterRoutingService? service;
  final Future<Uint8List> Function(int width)? document;

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  PrinterRoutingService get _service =>
      widget.service ?? PrinterRoutingService.instance;
  bool _busy = false;
  String? _message;
  bool _failed = false;

  Future<void> _print() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      final printer = await _service.selected(PrintRole.receipt);
      if (printer == null) {
        throw StateError(
          'اختر طابعة الفواتير الحرارية من إعدادات الطابعات أولاً.',
        );
      }
      final width =
          printer.url == '${BluetoothPrinterService.prefix}internal-q6'
          ? 384
          : await _service.paperWidth(PrintRole.receipt);
      final bytes = await (widget.document ?? PrinterTestDocument.build)(width);
      await _service.printPdf(
        role: PrintRole.receipt,
        bytes: bytes,
        format: PrinterTestDocument.format(width),
        name: 'WaslaPOS Printer Test',
      );
      if (mounted) {
        setState(
          () => _message =
              'تم إرسال صفحة الاختبار إلى ${printer.name}. تحقق من الورق ووضوح النص والباركود.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'تعذرت طباعة الاختبار: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('اختبار الطابعة')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'تُطبع الصفحة على طابعة الفواتير الحرارية المحفوظة في إعدادات هذا الجهاز. لا تحتاج إنترنت ولا تنشئ فاتورة أو حركة مالية.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'WaslaPOS',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text('اختبار الطابعة'),
                const Divider(),
                const Text('مرحباً بكم — تجربة الطباعة العربية'),
                const Text(
                  '0123456789  |  ABC abc',
                  textDirection: TextDirection.ltr,
                ),
                const Text('صنف تجريبي × 2 — 25.00'),
                const Text('اختبار السعر × 1 — 10.50'),
                const Divider(),
                const Text('الإجمالي التجريبي: 35.50'),
                const Icon(Icons.barcode_reader, size: 52),
                const Text('TEST123456', textDirection: TextDirection.ltr),
                const Text('هذه ورقة اختبار وليست فاتورة بيع'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _print,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print),
          label: Text(_busy ? 'جارٍ إرسال الاختبار…' : 'طباعة صفحة اختبار'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _message!,
              style: TextStyle(
                color: _failed ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
      ],
    ),
  );
}
