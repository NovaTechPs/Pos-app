import 'sale_data.dart';

abstract final class StockPreview {
  static ({double? local, double? total}) quantities(
    Map product,
    List<Map<String, dynamic>> cart, {
    bool project = false,
  }) {
    final local = SaleData.number(product['stock_quantity']);
    final total = SaleData.number(product['shared_stock_quantity']);
    final id = SaleData.id(product['product_id'] ?? product['id']);
    if (!project || id == null) return (local: local, total: total);
    final quantity = cart
        .where((line) => SaleData.id(line['product_id']) == id)
        .fold<double>(
          0,
          (sum, line) => sum + (SaleData.number(line['quantity']) ?? 0),
        );
    final takenLocally = total != null && quantity > 0 && local != null
        ? quantity.clamp(0, local.clamp(0, double.infinity)).toDouble()
        : quantity;
    return (
      local: local == null ? null : local - takenLocally,
      total: total == null ? null : total - quantity,
    );
  }
}
