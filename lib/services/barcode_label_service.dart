import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';
import 'printer_routing_service.dart';

abstract final class BarcodeLabelService {
  static Future<Uint8List> build({
    required String code,
    required String name,
    String price = '',
    String sku = '',
    bool showBarcode = true,
    int copies = 1,
    double widthMm = 50,
    double heightMm = 25,
  }) async {
    final barcode = pw.Barcode.code128();
    if ((showBarcode && (code.trim().isEmpty || !barcode.isValid(code))) ||
        (!showBarcode &&
            name.trim().isEmpty &&
            price.trim().isEmpty &&
            sku.trim().isEmpty) ||
        copies < 1 ||
        copies > 200 ||
        !widthMm.isFinite ||
        !heightMm.isFinite ||
        widthMm < 30 ||
        widthMm > 100 ||
        heightMm < 20 ||
        heightMm > 100) {
      throw StateError('تحقّق من الباركود وعدد النسخ (1–200) ومقاس الملصق.');
    }
    final doc = pw.Document(title: 'WaslaPOS Barcode');
    final theme = await PdfTheme.load();
    for (var i = 0; i < copies; i++) {
      doc.addPage(
        pw.Page(
          theme: theme,
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            heightMm * PdfPageFormat.mm,
            marginAll: 2 * PdfPageFormat.mm,
          ),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (name.trim().isNotEmpty)
                pw.SizedBox(
                  height: (heightMm < 25 ? 6 : 8) * PdfPageFormat.mm,
                  child: pw.Center(
                    child: pw.Text(
                      name,
                      maxLines: 2,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: heightMm < 25 ? 6 : 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              pw.Expanded(
                child: pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (price.trim().isNotEmpty || sku.trim().isNotEmpty)
                        pw.Expanded(
                          flex: 2,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              if (sku.trim().isNotEmpty)
                                pw.FittedBox(
                                  child: pw.Text(
                                    '#$sku',
                                    textDirection: pw.TextDirection.ltr,
                                    style: const pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              if (price.trim().isNotEmpty)
                                pw.FittedBox(
                                  child: pw.Text(
                                    price,
                                    textDirection: pw.TextDirection.ltr,
                                    style: pw.TextStyle(
                                      fontSize: 14,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (showBarcode) ...[
                        pw.SizedBox(width: 3),
                        pw.Expanded(
                          flex: 4,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.BarcodeWidget(
                                barcode: barcode,
                                data: code,
                                height:
                                    ((heightMm -
                                                    (name.trim().isEmpty
                                                        ? 4
                                                        : (heightMm < 25
                                                              ? 10
                                                              : 12))) *
                                                PdfPageFormat.mm -
                                            2)
                                        .clamp(4, 70)
                                        .toDouble(),
                                drawText: true,
                                textStyle: pw.TextStyle(
                                  font: pw.Font.helvetica(),
                                  fontSize: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<void> printLabels({
    required String code,
    required String name,
    String price = '',
    String sku = '',
    bool showBarcode = true,
    int copies = 1,
    double widthMm = 50,
    double heightMm = 25,
  }) async {
    final bytes = await build(
      code: code,
      name: name,
      price: price,
      sku: sku,
      showBarcode: showBarcode,
      copies: copies,
      widthMm: widthMm,
      heightMm: heightMm,
    );
    await PrinterRoutingService.instance.printPdf(
      role: PrintRole.barcode,
      bytes: bytes,
      format: PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        heightMm * PdfPageFormat.mm,
      ),
      name: 'WaslaPOS Barcode $code',
    );
  }
}
