import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Compact Arabic receipt voucher for the 72 mm printable thermal area.
abstract final class ReceiptVoucherLayout {
  static pw.Widget build({
    required String storeName,
    required String reference,
    required String customer,
    required String date,
    required String time,
    required String currency,
    required double amount,
    required double? previousBalance,
    required double? currentBalance,
    required String notes,
    required String cartSvg,
  }) {
    const shade = PdfColor.fromInt(0xFFECECEC);
    pw.Widget text(String value, {double size = 10, PdfColor? color}) =>
        pw.Text(value,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
                fontSize: size, fontWeight: pw.FontWeight.bold, color: color));
    pw.Widget rule() => pw.Divider(
        height: 12, thickness: .65, borderStyle: pw.BorderStyle.dashed);
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      parts[0] = parts[0].replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},');
      return parts.join('.');
    }

    pw.Widget balance(String label, double? value,
        {bool outlined = false, bool shaded = false}) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      decoration: pw.BoxDecoration(
        color: shaded ? shade : null,
        border: outlined ? pw.Border.all(width: .8) : null,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(children: [
        pw.Expanded(flex: 5, child: text(label, size: 10)),
        pw.SizedBox(width: 4),
        pw.Expanded(flex: 6, child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(value == null ? '—' : '$currency ${money(value)}',
            textDirection: pw.TextDirection.ltr,
            style: pw.TextStyle(fontSize: outlined || shaded ? 19 : 15,
              fontWeight: pw.FontWeight.bold)),
        )),
      ]),
    );
    pw.Widget metadata(String label, String value) => pw.Expanded(
      child: pw.Column(children: [
        text(label, size: 8),
        pw.Text(value, textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ]),
    );

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Flexible(child: text(storeName, size: 22)),
          pw.SizedBox(width: 7),
          pw.SvgImage(svg: cartSvg, width: 28, height: 28),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(child: pw.Divider(thickness: .8)),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 1),
            decoration: pw.BoxDecoration(color: PdfColors.black,
              borderRadius: pw.BorderRadius.circular(4)),
            child: text('سند قبض', size: 19, color: PdfColors.white)),
          pw.Expanded(child: pw.Divider(thickness: .8)),
        ]),
        pw.SizedBox(height: 9),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: pw.BoxDecoration(color: shade,
            borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            metadata('رقم السند', reference),
            metadata('التاريخ', date),
            metadata('الوقت', time),
          ])),
        rule(),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: text('اسم الزبون:  $customer', size: 12)),
        balance('الرصيد السابق:', previousBalance),
        balance('الدفعة المستلمة:', amount, outlined: true),
        balance('الرصيد بعد الدفعة:', currentBalance, shaded: true),
        if (currentBalance != null && currentBalance < 0)
          pw.Padding(padding: const pw.EdgeInsets.only(top: 3),
            child: text('الرصيد السالب لصالح صاحب الحساب', size: 8)),
        rule(),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: text('ملاحظات:  ${notes.isEmpty ? '—' : notes}', size: 11)),
        rule(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.SizedBox(width: 17, child: pw.Divider(thickness: .7)),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 9),
            child: text('شكراً لتعاملكم معنا', size: 13)),
          pw.SizedBox(width: 17, child: pw.Divider(thickness: .7)),
        ]),
        pw.SizedBox(height: 9),
      ],
    );
  }
}
