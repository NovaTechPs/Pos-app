import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

class SalesHistoryService {
  Future<Map<String, dynamic>> fetch({
    required int branchId,
    bool wholesale = false,
    String search = '',
    String? from,
    String? to,
    int page = 1,
  }) async {
    final path = wholesale ? 'wholesale/orders' : 'sales/orders';
    final response = await ApiClient.get(
      Uri.parse('${ApiConfig.baseUrl}/$path').replace(
        queryParameters: {
          'branch_id': '$branchId',
          'page': '$page',
          'per_page': '20',
          'status': 'completed',
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'from': ?from,
          'to': ?to,
        },
      ),
    );
    final result = ApiException.decode(response);
    final orders = result['orders'];
    if (orders is! Map || orders['data'] is! List) {
      throw const ApiException('صيغة سجل الفواتير غير صالحة.');
    }
    return Map<String, dynamic>.from(orders);
  }
}
