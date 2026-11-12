import 'dart:convert';
import 'dart:typed_data';

import 'pdf_theme.dart';

import 'api_client.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'printer_routing_service.dart';

import 'api_config.dart';

class StatementService {
  static Future<Map<String, dynamic>> fetchPartyStatement(int partyId) async {
    final response = await ApiClient.get(
      Uri.parse('${ApiConfig.baseUrl}/parties/$partyId/statement'),
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) throw Exception('تعذر تحميل كشف الحساب');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Uint8List> buildCustomerStatement({
    required Map<String, dynamic> customer,
    required List<dynamic> transactions,
  }) async {
    final doc = pw.Document();
    final theme = await PdfTheme.load();

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Wasla POS - كشف حساب ${customer['type'] == 'supplier' ? 'مورد' : 'عميل'}',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'التاريخ: ${DateTime.now().toString().substring(0, 10)}',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'اسم العميل: ${customer['name']}',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.Text(
              'رقم الجوال: ${customer['phone'] ?? 'غير متوفر'}',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.Text(
              'الرصيد الحالي: ${customer['current_balance'] ?? 0.0} ر.س',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['#', 'التاريخ', 'النوع', 'المبلغ', 'البيان'],
              data: transactions.isEmpty
                  ? [
                      [
                        '1',
                        '-',
                        'لا توجد حركات',
                        '—',
                        'الرصيد الحالي موضح أعلاه',
                      ],
                    ]
                  : transactions
                        .map(
                          (t) => [
                            t['id']?.toString() ?? '1',
                            t['date']?.toString() ?? '-',
                            t['type']?.toString() ?? '-',
                            t['amount']?.toString() ?? '0.00',
                            t['notes']?.toString() ?? '-',
                          ],
                        )
                        .toList(),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static Future<void> generateCustomerStatement({
    required Map<String, dynamic> customer,
    required List<dynamic> transactions,
  }) async {
    final bytes = await buildCustomerStatement(
      customer: customer,
      transactions: transactions,
    );
    await PrinterRoutingService.instance.printPdf(
      role: PrintRole.report,
      bytes: bytes,
      format: PdfPageFormat.a4,
      name: 'WaslaPOS Statement',
    );
  }
}
