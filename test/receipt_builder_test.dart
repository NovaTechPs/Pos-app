import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/services/receipt_builder.dart';
import 'package:waslapos_app/services/statement_service.dart';
import 'package:waslapos_app/models/invoice_reference.dart';
import 'package:waslapos_app/services/barcode_label_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reference invoice includes partial payment and final account balance',
    () async {
      final bytes = await ReceiptBuilder.build(
        order: {
          'invoice_number': 'SO-0001258',
          'type': 'wholesale',
          'store_name': 'شركة وصلة التجارية',
          'store_phone': '+970 599 123 456',
          'store_address': 'رام الله - المنطقة الصناعية',
          'customer_name': 'محل الأمانة التجاري',
          'created_at': '2026-11-08T20:15:00+02:00',
          'subtotal': 1105,
          'discount': 0,
          'tax_amount': 176.8,
          'total': 1281.8,
          'paid_amount': 500,
          'previous_balance': 200,
          'current_balance': 981.8,
        },
        items: [
          {
            'name': 'بيبسي 330 مل',
            'product_number': '100234',
            'unit': 'كرتونة',
            'quantity': 10,
            'price': 65,
          },
          {
            'name': 'مياه معدنية 500 مل',
            'product_number': '100235',
            'unit': 'كرتونة',
            'quantity': 5,
            'price': 22,
          },
          {
            'name': 'زيت نباتي 1 لتر',
            'product_number': '100236',
            'unit': 'كرتونة',
            'quantity': 3,
            'price': 115,
          },
        ],
        cashierName: 'مندوب',
        printedAt: DateTime(2026, 11, 9, 10),
      );
      expect(bytes.take(4), [37, 80, 68, 70]);
      if (const bool.fromEnvironment('WRITE_PDF_PREVIEWS')) {
        Directory('output/pdf').createSync(recursive: true);
        await File('output/pdf/invoice-payment-preview.pdf')
            .writeAsBytes(bytes);
      }
    },
  );
  test('payment and balance receipt preview', () async {
    final bytes = await ReceiptBuilder.build(
      order: {
        'invoice_number': 'PAY-919',
        'total': 919,
        'paid_amount': 919,
        'collected_amount': 1000,
        'previous_balance': 200,
        'current_balance': -81,
        'currency': 'JD',
        'customer_name': 'عميل تجريبي',
      },
      items: [
        {'name': 'صنف تجريبي', 'quantity': 1, 'price': 919},
      ],
      cashierName: 'أحمد',
    );
    expect(bytes.take(4), [37, 80, 68, 70]);
    if (const bool.fromEnvironment('WRITE_PDF_PREVIEWS')) {
      Directory('tmp/pdfs').createSync(recursive: true);
      await File('tmp/pdfs/payment-preview.pdf').writeAsBytes(bytes);
    }
  });
  test(
    'standalone receipt prints with the balance returned after the voucher',
    () async {
      final bytes = await ReceiptBuilder.build(
        order: {
          'type': 'receipt',
          'invoice_number': 'RCP-190',
          'total': 190,
          'paid_amount': 190,
          'previous_balance': 100,
          'current_balance': -90,
          'customer_name': 'عميل تجريبي',
        },
        items: const [],
        cashierName: 'أحمد',
      );

      expect(bytes.take(4), [37, 80, 68, 70]);
    },
  );
  test('printed references use server ID for long online numbers only', () {
    final order = {'id': 1042, 'invoice_number': 'INV-20261029174042-IMZZS'};
    expect(InvoiceReference.receipt(order), '1042');
    expect(InvoiceReference.display(order), 'INV-20261029174042-IMZZS');
    expect(
      InvoiceReference.receipt({'id': 1042, 'invoice_number': 'A2-12345'}),
      'A2-12345',
    );
    expect(
      InvoiceReference.receipt({
        'id': 'local:uuid',
        'invoice_number': 'OFF000001',
        'offline_pending': true,
      }),
      'OFF000001',
    );
    expect(
      InvoiceReference.receipt({'invoice_number': 'INV-20261029174042-IMZZS'}),
      'INV-20261029174042-IMZZS',
    );
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final path = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (!path.startsWith('assets/fonts/')) return null;
          return ByteData.sublistView(await File(path).readAsBytes());
        });
  });
  test('invoice display preserves server numbers and shortens legacy local references only', () {
    const old = 'OFF-6BC8612D-8D4E-4C4D-803E-44FAD2F29D93';
    final local = InvoiceReference.display({
      'invoice_number': old,
      'offline_pending': true,
    });
    expect(local, matches(RegExp(r'^OFF\d{6}$')));
    expect(
      InvoiceReference.display({
        'invoice_number': old,
        'offline_pending': true,
      }),
      local,
    );
    expect(
      InvoiceReference.display({'invoice_number': 'INV-SERVER-1042'}),
      'INV-SERVER-1042',
    );
    expect(InvoiceReference.display({'invoice_number': old}), old);
    expect(
      InvoiceReference.display({
        'invoice_number': 'OFF000001',
        'offline_pending': true,
      }),
      'OFF000001',
    );
  });

  test(
    'barcode labels build offline and reject empty codes or zero copies',
    () async {
      final bytes = await BarcodeLabelService.build(
        code: '001234567890',
        name: 'قهوة عربية',
        price: '12.50 ₪',
        copies: 2,
      );
      expect(bytes.take(4), [37, 80, 68, 70]);
      await expectLater(
        BarcodeLabelService.build(code: '', name: 'test'),
        throwsStateError,
      );
      await expectLater(
        BarcodeLabelService.build(code: '123', name: 'test', copies: 0),
        throwsStateError,
      );
      if (const bool.fromEnvironment('WRITE_LABEL_PREVIEW')) {
        Directory('tmp/pdfs').createSync(recursive: true);
        await File('tmp/pdfs/barcode-labels.pdf').writeAsBytes(bytes);
      }
    },
  );

  test(
    'label visibility supports SKU-only and rejects a completely blank label',
    () async {
      final bytes = await BarcodeLabelService.build(
        code: '',
        name: '',
        sku: 'P-1042',
        showBarcode: false,
      );
      expect(bytes.take(4), [37, 80, 68, 70]);
      await expectLater(
        BarcodeLabelService.build(code: '', name: '', showBarcode: false),
        throwsStateError,
      );
      final full = await BarcodeLabelService.build(
        code: '00ABC123',
        name: 'قهوة عربية حجم كبير',
        price: '12.50 NIS',
        sku: 'P-1042',
      );
      if (const bool.fromEnvironment('WRITE_LABEL_PREVIEW')) {
        await File('tmp/pdfs/barcode-full.pdf').writeAsBytes(full);
      }
    },
  );

  test(
    'online and offline receipt previews share the thermal table layout',
    () async {
      for (final offline in [false, true]) {
        final bytes = await ReceiptBuilder.build(
          order: {
            'id': offline ? 'local:uuid' : 1042,
            'invoice_number': offline ? 'OFF000001' : 'INV-20261029-1042',
            'offline_pending': offline,
            'created_at': '2026-10-29T20:50:36+03:00',
            'branch': {'name': 'الفرع الرئيسي'},
            'customer_name': 'عميل نقدي',
            'subtotal': 6.5,
            'discount': 0,
            'tax_amount': 0,
            'total': 6.5,
            'paid_amount': 6.5,
          },
          items: [
            {'name': 'مكنسة ستانلس عادي حجم 30', 'quantity': 1, 'price': 1},
            {'name': 'دعاسة أرض خيطان 38×55', 'quantity': 2.5, 'price': 1},
            {'name': 'علاقة غسيل خشب 20 حبل', 'quantity': 1, 'price': 3},
            {'name': 'كوب زجاج', 'quantity': 1, 'price': 0, 'gift': true},
          ],
          cashierName: 'أحمد',
        );
        expect(bytes.take(4), [37, 80, 68, 70]);
        if (const bool.fromEnvironment('WRITE_PDF_PREVIEWS')) {
          Directory('tmp/pdfs').createSync(recursive: true);
          await File('tmp/pdfs/receipt-${offline ? 'offline' : 'online'}.pdf')
              .writeAsBytes(bytes);
        }
      }
    },
  );

  test('builds an Arabic receipt and a multi-page statement without a printer or network', () async {
    final receipt = await ReceiptBuilder.build(
      order: {
        'invoice_number': 'INV-1042',
        'created_at': '2026-10-23T10:15:00+03:00',
        'branch': {'name': 'الفرع الرئيسي'},
        'customer_name': 'عميل نقدي',
        'subtotal': 45,
        'discount': 5,
        'tax_amount': 0,
        'total': 40,
        'paid_amount': 40,
      },
      items: [
        {'name': 'قهوة عربية محمصة', 'quantity': 2, 'price': 15},
        {'name': 'شاي بالنعناع', 'quantity': 1, 'price': 15},
      ],
      cashierName: 'أحمد',
    );
    final statement = await StatementService.buildCustomerStatement(
      customer: {
        'name': 'شركة الاختبار',
        'phone': '0591234567',
        'current_balance': 1350,
      },
      transactions: List.generate(
        70,
        (i) => {
          'id': i + 1,
          'date': '2026-10-23',
          'type': i.isEven ? 'فاتورة' : 'سند قبض',
          'amount': 25,
          'notes': 'حركة حساب تجريبية رقم ${i + 1}',
        },
      ),
    );
    expect(receipt.take(4), [37, 80, 68, 70]);
    expect(statement.length, greaterThan(1000));
    if (const bool.fromEnvironment('WRITE_PDF_PREVIEWS')) {
      final output = Directory('tmp/pdfs')..createSync(recursive: true);
      File('${output.path}/receipt-preview.pdf').writeAsBytesSync(receipt);
      File('${output.path}/statement-preview.pdf').writeAsBytesSync(statement);
    }
  });
}
