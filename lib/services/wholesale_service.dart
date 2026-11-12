import 'api_exception.dart';
import '../models/sale_data.dart';

import 'api_client.dart';

import 'api_config.dart';

class WholesaleService {
  static String get baseUrl => ApiConfig.baseUrl;
  bool allowNegativeStock = false;
  bool canSellBelowCost = false;
  bool workspaceAvailable = false;

  Future<Map<String, dynamic>> document(
    int branchId, {
    bool receipt = false,
    Map<String, Object> query = const {},
  }) async {
    final uri =
        Uri.parse('$baseUrl/wholesale/${receipt ? 'receipts' : 'invoice'}')
            .replace(
              queryParameters: {
                'branch_id': '$branchId',
                ...query.map((key, value) => MapEntry(key, '$value')),
              },
            );
    return ApiException.decode(await ApiClient.get(uri));
  }

  Future<List<dynamic>> priceHistory(
    int branchId,
    int customerId,
    int productId,
  ) async {
    final uri = Uri.parse('$baseUrl/wholesale/price-history').replace(
      queryParameters: {
        'branch_id': '$branchId',
        'customer_id': '$customerId',
        'product_id': '$productId',
      },
    );
    final data = ApiException.decode(await ApiClient.get(uri));
    if (data['history'] is! List) {
      throw const ApiException('تعذر قراءة سجل الأسعار.');
    }
    return data['history'] as List;
  }

  Future<Map<String, dynamic>> updateInvoiceReceipt({
    required bool salesInvoice,
    required int orderId,
    required Map<String, dynamic> payload,
  }) async {
    final path = salesInvoice
        ? 'pos/invoices/$orderId/receipt'
        : 'wholesale/invoice/$orderId/receipt';
    return ApiException.decode(
      await ApiClient.patch(Uri.parse('$baseUrl/$path'), body: payload),
    );
  }

  Future<List<dynamic>> fetchProducts(int branchId) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/wholesale/products?branch_id=$branchId'),
    );
    final data = await ApiException.decodeAsync(response);
    allowNegativeStock = data['allow_negative_stock'] == true;
    canSellBelowCost = data['can_sell_below_cost'] == true;
    workspaceAvailable = (SaleData.number(data['workspace_version']) ?? 0) >= 1;
    if (data['products'] is! List) {
      throw const ApiException('تعذر قراءة أصناف الجملة.');
    }
    return (data['products'] as List).map((raw) {
      final product = Map<String, dynamic>.from(raw);
      // An unset minimum means "no minimum"; one such product must not
      // block the whole wholesale screen. Price and stock stay strict.
      product['min_wholesale_quantity'] ??= 1;
      for (final key in ['price', 'stock_quantity', 'min_wholesale_quantity']) {
        final number = SaleData.number(product[key]);
        if (number == null || (number < 0 && key != 'stock_quantity')) {
          throw const ApiException('بيانات تسعير أو مخزون غير صالحة.');
        }
        product[key] = number;
      }
      product['id'] = SaleData.id(product['id']);
      return product;
    }).toList();
  }
}
