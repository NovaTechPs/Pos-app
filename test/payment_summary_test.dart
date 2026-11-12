import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/models/payment_summary.dart';

void main() {
  for (final paid in [0.0, 100.0, 919.0]) {
    test('saved invoice balance includes actual payment $paid', () {
      final summary = PaymentSummary.saved({
        'total': 919,
        'paid_amount': paid,
        'party': {'current_balance': 100 + 919 - paid},
      });
      expect(summary['previous_balance'], 100);
      expect(summary['current_balance'], 1019 - paid);
      expect(summary['paid_amount'], paid);
    });
  }
  test('receipt balance and supplier direction use server values', () {
    final receipt = PaymentSummary.saved({
      'amount': 25,
      'party': {'current_balance': 75},
    }, receipt: true);
    expect(receipt['previous_balance'], 100);
    expect(receipt['current_balance'], 75);
    final supplier = PaymentSummary.saved({
      'amount': 25,
      'party': {'current_balance': 125, 'type': 'supplier'},
    }, receipt: true);
    expect(supplier['previous_balance'], 100);
  });
  test(
    'overpayment uses the collected amount to preserve the customer credit',
    () {
      final summary = PaymentSummary.saved({
        'total': 919,
        'paid_amount': 919,
        'collected_amount': 1000,
        'party': {'current_balance': 19},
      });
      expect(summary['previous_balance'], 100);
      expect(summary['current_balance'], 19);
    },
  );
  test('explicit balances win and missing balances are not invented', () {
    expect(PaymentSummary.saved({'paid_amount': 0})['current_balance'], isNull);
    expect(
      PaymentSummary.saved({
        'total': 50,
        'paid_amount': 0,
        'previous_balance': 20,
        'current_balance': 70,
        'party': {'current_balance': 999},
      })['previous_balance'],
      20,
    );
    expect(PaymentSummary.matches(919, 0), isFalse);
    expect(PaymentSummary.matches(null, 0), isFalse);
    expect(PaymentSummary.matches('0.00', 0), isTrue);
  });
}
