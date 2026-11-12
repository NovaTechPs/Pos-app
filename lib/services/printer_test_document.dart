import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

abstract final class PrinterTestDocument {
  static PdfPageFormat format(int width) => PdfPageFormat(
    (width == 576 ? 80 : 58) * PdfPageFormat.mm,
    145 * PdfPageFormat.mm,
    marginAll: 3 * PdfPageFormat.mm,
  );

  static Future<Uint8List> build(int width, {DateTime? printedAt}) async {
    final theme = await PdfTheme.load();
    final now = printedAt ?? DateTime.now();
    final doc = pw.Document(title: 'WaslaPOS Printer Test');
    doc.addPage(
      pw.Page(
        pageFormat: format(width),
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'WaslaPOS',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'اختبار الطابعة',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.Text(
              'مرحباً بكم — تجربة الطباعة العربية',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'وضوح الحروف: أ إ آ ة ى ي ؤ ئ',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              '0123456789  |  ABC abc',
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['المبلغ', 'الكمية', 'البيان'],
              data: [
                ['25.00', '2', 'صنف تجريبي'],
                ['10.50', '1', 'اختبار السعر'],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.center,
              cellPadding: const pw.EdgeInsets.all(4),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: pw.Text(
                'الإجمالي التجريبي: 35.50',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: 'TEST123456',
              height: 36,
              drawText: true,
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '${now.year}/${now.month}/${now.day}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              textDirection: pw.TextDirection.ltr,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'هذه ورقة اختبار وليست فاتورة بيع',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(thickness: 1),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
