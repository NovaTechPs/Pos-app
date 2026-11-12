import 'sale_data.dart';

/// Balances returned by the server; never substitutes the requested payment.
abstract final class PaymentSummary {
  static Map<String, dynamic> saved(
    Map<String, dynamic> order, {
    bool receipt = false,
  }) {
    final result = Map<String, dynamic>.from(order);
    final party = order['party'];
    final current =
        SaleData.number(order['current_balance']) ??
        (party is Map ? SaleData.number(party['current_balance']) : null);
    if (current == null) return result;
    result['current_balance'] = current;
    final direction = party is Map && party['type'] == 'supplier' ? -1 : 1;
    final paid = SaleData.number(
      receipt
          ? order['amount']
          : order['collected_amount'] ?? order['paid_amount'],
    );
    final total = SaleData.number(order['total'] ?? order['total_amount']);
    if (order['previous_balance'] == null &&
        paid != null &&
        (receipt || total != null)) {
      result['previous_balance'] = double.parse(
        (receipt
                ? current + direction * paid
                : current - direction * (total! - paid))
            .toStringAsFixed(2),
      );
    }
    return result;
  }

  static bool matches(Object? actual, num requested) {
    final amount = SaleData.number(actual);
    return amount != null && (amount - requested).abs() < .005;
  }
}
