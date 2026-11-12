import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';

import 'receipt_builder.dart';
import 'printer_routing_service.dart';
import 'pdf_theme.dart';

import 'dart:developer' as developer;

class PrinterService {
  static Future<void> prepareReceipt() async {
    await Future.wait<Object?>([
      PdfTheme.load(),
      PrinterRoutingService.instance.prepare(PrintRole.receipt),
    ]);
  }

  static Future<void> shareReceipt({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String cashierName,
    String? message,
  }) async {
    final bytes = await ReceiptBuilder.build(
      order: order,
      items: items,
      cashierName: cashierName,
    );
    final reference = '${order['invoice_number'] ?? order['id'] ?? 'invoice'}'
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fileName = 'WaslaPOS-$reference.pdf';
    await SharePlus.instance.share(
      ShareParams(
        title: 'إرسال فاتورة WaslaPOS',
        subject: 'فاتورة ${order['invoice_number'] ?? ''}',
        text: message,
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String cashierName,
  }) async {
    final timer = Stopwatch()..start();
    final bytes = await ReceiptBuilder.build(
      order: order,
      items: items,
      cashierName: cashierName,
    );
    developer.log(
      'receipt_pdf_ms=${timer.elapsedMilliseconds}',
      name: 'waslapos.print',
    );
    await PrinterRoutingService.instance.printPdf(
      role: PrintRole.receipt,
      bytes: bytes,
      format: PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm),
      name: 'WaslaPOS ${order['invoice_number'] ?? 'Receipt'}',
    );
    developer.log(
      'receipt_accepted_ms=${timer.elapsedMilliseconds}',
      name: 'waslapos.print',
    );
  }
}
