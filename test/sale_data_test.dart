import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/models/sale_data.dart';

void main() {
  test(
    'numeric fast paths preserve finite validation and localized numbers',
    () {
      expect(SaleData.number(12.5), 12.5);
      expect(SaleData.number(12), 12.0);
      expect(SaleData.number('١٢٫٥'), 12.5);
      expect(SaleData.number('۱۲.۵'), 12.5);
      expect(SaleData.number(double.nan), isNull);
      expect(SaleData.number(double.infinity), isNull);
      expect(SaleData.number(null), isNull);
      expect(SaleData.id(12), 12);
      expect(SaleData.id('0012'), 12);
      expect(SaleData.id(12.5), isNull);
    },
  );
  test('invoice save check counts an empty discount as zero and names the real problem', () {
    String? problem({
      String discount = '0',
      bool percentage = false,
      String paid = '105',
      bool customer = true,
    }) => SaleData.invoiceSaveProblem(
      discountText: discount,
      percentageDiscount: percentage,
      subtotal: 105,
      paidText: paid,
      total: 105,
      hasCustomer: customer,
    );

    expect(problem(discount: ''), isNull);
    expect(problem(discount: '  ', paid: ''), isNull);
    expect(problem(customer: false), isNull);
    expect(problem(discount: 'abc'), 'قيمة الخصم غير صحيحة');
    expect(problem(discount: '200'), 'الخصم أكبر من مجموع الفاتورة');
    expect(
      problem(discount: '101', percentage: true),
      'نسبة الخصم لا يمكن أن تزيد عن 100%',
    );
    expect(problem(paid: '-1'), 'المبلغ المدفوع غير صحيح');
    expect(
      problem(paid: '50', customer: false),
      'اختر عميلاً عند وجود مبلغ متبقٍ أو دفعة زائدة عن الفاتورة',
    );
  });
  test(
    'bundle offers span duplicate rows, exclude gifts, and preserve rounding',
    () {
      final lines = <Map<String, dynamic>>[
        {
          'product_id': 1,
          'price': 10,
          'quantity': 1,
          'offer_quantity': 3,
          'offer_price': 25,
        },
        {
          'product_id': 1,
          'price': 10,
          'quantity': 2,
          'offer_quantity': 3,
          'offer_price': 25,
        },
        {
          'product_id': 1,
          'price': 10,
          'quantity': 1,
          'discount': 10,
          'gift': true,
        },
      ];
      SaleData.applyOffers(lines);
      expect(
        lines.fold<double>(0, (sum, line) => sum + SaleData.lineTotal(line)),
        25,
      );
      final payload = SaleData.uniqueItems(lines, supportsGiftLines: true);
      expect(payload.length, 2);
      expect(payload.first['quantity'], 3);
      expect(payload.first['use_offer'], true);
      expect(payload.last['is_gift'], true);
      lines.first['price_manual'] = true;
      SaleData.applyOffers(lines);
      expect(
        lines.fold<double>(0, (sum, line) => sum + SaleData.lineTotal(line)),
        30,
      );
    },
  );

  test('API items combine repeated ids without changing quantities, totals or receipt lines', () {
    final lines = [
      {'product_id': 1, 'price': 10, 'quantity': 2, 'discount': 0},
      {'product_id': '1', 'price': 10, 'quantity': 3, 'discount': 0},
      {'product_id': 2, 'price': 8, 'quantity': 0.5, 'discount': 2},
    ];
    final items = SaleData.uniqueItems(lines);
    expect(items.length, 2);
    expect(items.first, {'product_id': 1, 'price': 10.0, 'quantity': 5.0});
    expect(items.last['price'], 6);
    expect(lines.length, 3);
    expect(lines.first['quantity'], 2);
    expect(
      items.fold<double>(0, (sum, line) => sum + SaleData.lineTotal(line)),
      53,
    );
  });
  test(
    'mixed gift prices and rounding discrepancies never get silently averaged',
    () {
      expect(
        () => SaleData.uniqueItems([
          {'product_id': 1, 'price': 10, 'quantity': 1, 'discount': 10},
          {'product_id': 1, 'price': 10, 'quantity': 1, 'discount': 0},
        ]),
        throwsFormatException,
      );
      expect(
        () => SaleData.uniqueItems([
          {'product_id': 1, 'price': 0.05, 'quantity': 0.3333},
          {'product_id': 1, 'price': 0.05, 'quantity': 0.3333},
        ]),
        throwsFormatException,
      );
    },
  );

  test('selects the declared pricing branch and never invents a price', () {
    final product = {
      'branches': [
        {
          'id': '2',
          'pivot': {'retail_price': '25.50'},
        },
        {
          'id': 1,
          'pivot': {'retail_price': 10},
        },
      ],
    };
    expect(SaleData.retailPrice(product, 1), 10);
    expect(SaleData.retailPrice(product, 2), 25.5);
    expect(SaleData.retailPrice(product, 3), isNull);
    expect(SaleData.retailPrice({}, 1), isNull);
    expect(SaleData.retailPrice({'retail_price': 0}, 1), 0);
    expect(SaleData.retailPrice({'retail_price': -1}, 1), isNull);
  });
  test('parses Arabic amounts and rejects non-finite amounts', () {
    expect(SaleData.number('١٢٫٥٠'), 12.5);
    expect(SaleData.number('۱۲.۵۰'), 12.5);
    for (final invalid in ['NaN', 'Infinity', double.infinity, null, 'bad']) {
      expect(SaleData.number(invalid), isNull);
    }
  });
  test('saved invoices retain fractional quantities and effective prices', () {
    final lines = SaleData.heldLines({
      'items': [
        {
          'product_id': '1',
          'quantity': '0.75',
          'unit_price': '12.50',
          'product': {'name': 'قهوة'},
        },
      ],
    });
    expect(lines.single['quantity'], 0.75);
    expect(lines.single['price'], 12.5);
    expect(SaleData.lineTotal(lines.single), 9.38);
  });
  test('rejects malformed held invoices before replacing the cart', () {
    for (final order in [
      <String, dynamic>{},
      {'items': []},
      {
        'items': [
          {'product_id': 1, 'quantity': 0, 'unit_price': 10},
        ],
      },
    ]) {
      expect(() => SaleData.heldLines(order), throwsFormatException);
    }
  });
  test('line discount cannot exceed price or become non-finite', () {
    expect(
      () => SaleData.lineTotal({'price': 10, 'quantity': 1, 'discount': 11}),
      throwsFormatException,
    );
    expect(
      () => SaleData.lineTotal({'price': double.nan, 'quantity': 1}),
      throwsFormatException,
    );
  });
}
