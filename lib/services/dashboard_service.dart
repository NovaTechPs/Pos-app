import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

class DashboardService {
  Future<Map<String, dynamic>> fetchSummary(
    int branchId, {
    String? from,
    String? to,
  }) async {
    if (branchId <= 0) throw const ApiException('اختر فرعاً لعرض الإحصائيات.');
    final response = await ApiClient.get(
      Uri.parse('${ApiConfig.baseUrl}/reports/summary').replace(
        queryParameters: {'branch_id': '$branchId', 'from': ?from, 'to': ?to},
      ),
    );
    final data = ApiException.decode(response);
    if (data['summary'] is! Map) {
      throw const ApiException('لم يرسل الخادم ملخص الإحصائيات.');
    }
    return {
      ...Map<String, dynamic>.from(data['summary']),
      'top_products': data['top_products'] is List ? data['top_products'] : [],
      'stock_alerts': data['stock_alerts'] is List ? data['stock_alerts'] : [],
    };
  }
}
