import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

class ProductMaintenanceService {
  Future<Map<String, dynamic>> save(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (ApiClient.offline.value) {
      throw const ApiException(
        'إضافة الأصناف وربط الباركود يتطلبان الاتصال بالخادم. السلة الحالية محفوظة.',
      );
    }
    final response = await ApiClient.post(
      Uri.parse('${ApiConfig.baseUrl}/$path'),
      body: payload,
    );
    if (response.statusCode == 405) {
      throw const ApiException(
        'يلزم تحديث API على الاستضافة لتفعيل إضافة الأصناف وربط الباركود.',
      );
    }
    final data = ApiException.decode(response);
    if (data['product'] is! Map || data['product']['id'] == null) {
      throw const ApiException(
        'لم يصل تأكيد الصنف من الخادم. حدّث الأصناف قبل إعادة المحاولة.',
      );
    }
    return Map<String, dynamic>.from(data['product']);
  }
}
