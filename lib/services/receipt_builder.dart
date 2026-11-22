import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_data.dart';
import '../models/payment_summary.dart';
import '../models/invoice_reference.dart';
import 'pdf_theme.dart';
import 'receipt_voucher_layout.dart';

abstract final class ReceiptBuilder {
  /// An 80 mm thermal roll prints only about 72 mm (576 dots); a wider page loses its right edge.
  static const double printableWidthMm = 72;

  static Future<Uint8List> build({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String cashierName,
    DateTime? printedAt,
  }) async {
    order = PaymentSummary.saved(order, receipt: order['type'] == 'receipt');
    final theme = await PdfTheme.load();
    final invoice = InvoiceReference.receipt(order);
    final doc = pw.Document(title: 'فاتورة $invoice');
    final currency = order['currency']?.toString() ?? '₪';
    String amount(Object? value) =>
        (SaleData.number(value) ?? 0).toStringAsFixed(2);
    String quantity(Object? value) {
      final number = SaleData.number(value) ?? 0;
      return number == number.roundToDouble() ? '${number.toInt()}' : '$number';
    }

    double lineTotal(Map<String, dynamic> item) =>
        SaleData.number(item['promotion_total']) ??
        (SaleData.number(item['quantity']) ?? 0) *
            (SaleData.number(item['price']) ?? 0);
    pw.Widget text(
      String value, {
      double size = 11,
      bool bold = true,
      PdfColor? color,
      pw.TextDirection? direction,
    }) => pw.Text(
      value,
      textAlign: pw.TextAlign.center,
      textDirection: direction,
      style: pw.TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    pw.Widget cell(String value, {bool heading = false, bool rtl = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          child: text(
            value,
            size: heading ? 9 : 10,
            bold: true,
            color: PdfColors.black,
            direction: heading || rtl
                ? pw.TextDirection.rtl
                : pw.TextDirection.ltr,
          ),
        );
    pw.Widget box(
      String label,
      Object? value, {
      bool prominent = false,
      String? unit,
    }) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 3),
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                fontSize: prominent ? 12 : 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          text(
            '${unit == null ? '' : '$unit '}${amount(value)}',
            size: prominent ? 14 : 12,
            bold: true,
            direction: pw.TextDirection.ltr,
            color: PdfColors.black,
          ),
        ],
      ),
    );
    String date(DateTime value) =>
        '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
    String time(DateTime value) =>
        '${(value.hour % 12 == 0 ? 12 : value.hour % 12).toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
    final created = DateTime.tryParse('${order['created_at']}')?.toLocal();
    final subtotal =
        SaleData.number(order['subtotal']) ??
        items.fold<double>(0, (sum, item) => sum + lineTotal(item));
    final total =
        SaleData.number(order['total'] ?? order['total_amount']) ?? subtotal;
    final paid = SaleData.number(
      order['type'] == 'receipt'
          ? order['paid_amount']
          : order['collected_amount'] ?? order['paid_amount'],
    );
    final invoiceBalance = order['type'] == 'receipt' || paid == null
        ? null
        : total - paid;
    final currentBalance =
        SaleData.number(order['current_balance']) ??
        SaleData.number(order['party']?['current_balance']);
    final customer = order['party']?['name'] ?? order['customer_name'];
    final discount =
        SaleData.number(order['discount'] ?? order['discount_amount']) ?? 0;
    // Without a customer account, cash handed back as change is not a payment.
    final payment = currentBalance == null
        ? (paid ?? 0).clamp(0, total < 0 ? 0 : total).toDouble()
        : (paid ?? 0);
    final balanceDirection = order['party']?['type'] == 'supplier' ? -1 : 1;
    final previousBalance = currentBalance == null
        ? null
        : SaleData.number(order['previous_balance']) ??
              currentBalance - balanceDirection * (invoiceBalance ?? 0);
    final storeName =
        (order['store_name'] ??
                order['branch']?['name'] ??
                order['branch_name'])
            ?.toString()
            .trim();
    final isReturn =
        order['type'] == 'return' || (order['type'] != 'receipt' && total < 0);
    final title = order['type'] == 'receipt'
        ? 'سند قبض'
        : (isReturn ? 'فاتورة مرتجع' : 'فاتورة بيع');
    const lines = PdfColors.black;
    const shade = PdfColor.fromInt(0xFFE5E7EB);
    const cartIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M2.5 3.5h2.4l2.5 11.2h10.4l2.2-7.7H6.2"/>'
        '<circle cx="9.3" cy="19.2" r="1.6" fill="#000"/><circle cx="16.6" cy="19.2" r="1.6" fill="#000"/></svg>';
    doc.addPage(
      pw.Page(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat(
          ReceiptBuilder.printableWidthMm * PdfPageFormat.mm,
          double.infinity,
          marginLeft: 1.5 * PdfPageFormat.mm,
          marginRight: 1.5 * PdfPageFormat.mm,
        ),
        build: (_) => order['type'] == 'receipt'
            ? ReceiptVoucherLayout.build(
                storeName: storeName?.isNotEmpty == true ? storeName! : 'Wasla POS',
                reference: invoice,
                customer: customer?.toString() ?? 'غير محدد',
                date: DateTime.tryParse('${order['payment_date']}') != null
                    ? date(DateTime.parse('${order['payment_date']}'))
                    : created == null ? 'غير متوفر' : date(created),
                time: created == null ? 'غير متوفر' : time(created),
                currency: currency,
                amount: SaleData.number(order['amount']) ?? total,
                previousBalance: SaleData.number(order['previous_balance']),
                currentBalance: currentBalance,
                notes: '${order['notes'] ?? ''}'.trim(),
                cartSvg: cartIcon,
              )
            : pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Store name with a cart, then the document title, like a printed shop invoice.
            if (storeName != null && storeName.isNotEmpty)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Flexible(child: text(storeName, size: 15)),
                  pw.SizedBox(width: 4),
                  pw.SizedBox(
                    width: 20,
                    height: 20,
                    child: pw.SvgImage(svg: cartIcon),
                  ),
                ],
              ),
            text(title, size: 13),
            pw.SizedBox(height: 3),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Row(
                    children: [
                      text('رقم: ', size: 10),
                      pw.Flexible(
                        child: text(
                          invoice,
                          size: 10,
                          direction: pw.TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                ),
                text(
                  created == null
                      ? 'غير متوفر'
                      : '${date(created)}   ${time(created)}',
                  size: 9,
                  direction: pw.TextDirection.ltr,
                ),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Divider(
              height: 6,
              thickness: .8,
              color: lines,
              borderStyle: pw.BorderStyle.dashed,
            ),
            if (customer != null &&
                customer != 'عميل نقدي' &&
                customer != 'زبون نقدي')
              text('الزبون: $customer', size: 10),
            if (order['offline_rejected'] == true)
              text('فاتورة محلية غير معتمدة - تحتاج مراجعة', bold: true)
            else if (order['offline_pending'] == true)
              text('نسخة محلية - بانتظار المزامنة', size: 8),
            pw.SizedBox(height: 4),
            if (order['type'] != 'receipt') ...[
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: lines, width: 1.2),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Table(
                      border: const pw.TableBorder(
                        horizontalInside: pw.BorderSide(
                          color: lines,
                          width: .6,
                        ),
                        verticalInside: pw.BorderSide(color: lines, width: .6),
                      ),
                      defaultVerticalAlignment:
                          pw.TableCellVerticalAlignment.middle,
                      columnWidths: {
                        0: const pw.FlexColumnWidth(1.25),
                        1: const pw.FlexColumnWidth(1.2),
                        2: const pw.FlexColumnWidth(.95),
                        3: const pw.FlexColumnWidth(2.4),
                        4: const pw.FlexColumnWidth(.6),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: shade),
                          children: [
                            cell('الإجمالي', heading: true),
                            cell('سعر الوحدة', heading: true),
                            cell('الكمية', heading: true),
                            cell('الصنف', heading: true),
                            cell('رقم', heading: true),
                          ],
                        ),
                        ...items.asMap().entries.map((entry) {
                          final item = entry.value;
                          final count = SaleData.number(item['quantity']) ?? 0;
                          final sum = lineTotal(item);
                          final price = count > 0
                              ? sum / count
                              : SaleData.number(item['price']) ?? 0;
                          final name =
                              "${item['name'] ?? 'منتج'}${item['gift'] == true || item['is_gift'] == true ? ' (هدية)' : ''}";
                          final unit = item['unit'];
                          final unitName = unit is Map ? unit['name'] : unit;
                          return pw.TableRow(
                            children: [
                              cell(amount(sum)),
                              cell(amount(price)),
                              cell(
                                '${quantity(count)}${unitName == null ? '' : ' $unitName'}',
                                rtl: true,
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 3,
                                ),
                                child: pw.Text(
                                  name,
                                  textDirection: pw.TextDirection.rtl,
                                  textAlign: pw.TextAlign.right,
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                              cell('${entry.key + 1}'),
                            ],
                          );
                        }),
                      ],
                    ),
                    // The total closes the table in a shaded row.
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        color: shade,
                        border: pw.Border(
                          top: pw.BorderSide(color: lines, width: 1.2),
                        ),
                      ),
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 6,
                      ),
                      child: pw.Row(
                        children: [
                          text('الإجمالي:', size: 13),
                          pw.Spacer(),
                          text(
                            amount(total),
                            size: 15,
                            direction: pw.TextDirection.ltr,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              // Under an invoice only: discount, payment, previous and new balance.
              if (discount.abs() > .004) ...[
                box('المجموع قبل الخصم', total + discount, unit: currency),
                box('الخصم', discount, unit: currency),
              ],
              box('دفعة', payment, unit: currency),
              if (currentBalance != null) ...[
                box('رصيد سابق', previousBalance ?? 0, unit: currency),
                box(
                  'رصيد جديد',
                  currentBalance,
                  prominent: true,
                  unit: currency,
                ),
              ],
            ],
            if (order['type'] == 'receipt')
              box('المبلغ المقبوض', total, prominent: true, unit: currency),
            if (order['type'] == 'receipt' && currentBalance != null)
              box(
                order['type'] == 'receipt'
                    ? (currentBalance < -.001 &&
                              order['party']?['type'] != 'supplier'
                          ? 'رصيد لصالح الزبون بعد السند'
                          : 'الرصيد المتبقي على الزبون بعد السند')
                    : 'الرصيد الحالي على الزبون',
                currentBalance < -.001 && order['party']?['type'] != 'supplier'
                    ? -currentBalance
                    : currentBalance,
                unit: currency,
              ),
            if (order['notes']?.toString().trim().isNotEmpty == true) ...[
              pw.SizedBox(height: 5),
              text('ملاحظات: ${order['notes']}'),
            ],
          ],
        ),
      ),
    );
    return doc.save();
  }
}
