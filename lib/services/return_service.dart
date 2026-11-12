import 'api_config.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'checkout_service.dart';

class ReturnService {
  Future<Map<String, dynamic>?> findInvoice(String invoiceNumber) async {
    final response = await ApiClient.get(
      Uri.parse(
        '${ApiConfig.baseUrl}/orders/invoice/${Uri.encodeComponent(invoiceNumber)}',
      ),
    );
    if (response.statusCode == 404) return null;
    final data = ApiException.decode(response);
    if (data['order'] is! Map) {
      throw const ApiException('تعذر قراءة بيانات الفاتورة.');
    }
    return Map<String, dynamic>.from(data['order']);
  }

  CheckoutService journal(int branchId) => CheckoutService(
    scope: [
      ApiConfig.baseUrl,
      ApiClient.user?['tenant_id'],
      ApiClient.user?['id'],
      branchId,
      'return',
    ].join('|'),
    resultKey: 'return_order',
    send: (payload) => ApiClient.post(
      Uri.parse('${ApiConfig.baseUrl}/orders/returns'),
      body: payload,
    ),
  );
}
