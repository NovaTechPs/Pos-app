import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// The sales rep's daily customer list: customers to visit, each checked off
/// with what came of the visit (a sale, a collection only, or an order) and a note.
class VisitService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// What a visit can end with, keyed as the server stores it.
  static const outcomes = {
    'sale': 'بيع',
    'collection': 'تحصيل فقط',
    'order': 'يوجد طلبية',
  };

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> fetch(DateTime date) async {
    final uri = Uri.parse('$baseUrl/customer-visits')
        .replace(queryParameters: {'date': dateKey(date)});
    return _visits(ApiException.decode(await ApiClient.get(uri)));
  }

  Future<List<Map<String, dynamic>>> add(
    DateTime date,
    List<int> customerIds,
  ) async {
    final response = await ApiClient.post(
      Uri.parse('$baseUrl/customer-visits'),
      body: {'date': dateKey(date), 'party_ids': customerIds},
    );
    return _visits(ApiException.decode(response));
  }

  Future<Map<String, dynamic>> update(
    int visitId, {
    required String? outcome,
    required String notes,
  }) async {
    final data = ApiException.decode(
      await ApiClient.patch(
        Uri.parse('$baseUrl/customer-visits/$visitId'),
        body: {'outcome': outcome, 'notes': notes},
      ),
    );
    if (data['visit'] is! Map) {
      throw const ApiException('تعذر قراءة الزيارة.');
    }
    return Map<String, dynamic>.from(data['visit']);
  }

  Future<void> remove(int visitId) async {
    ApiException.decode(
      await ApiClient.delete(Uri.parse('$baseUrl/customer-visits/$visitId')),
    );
  }

  List<Map<String, dynamic>> _visits(Map<String, dynamic> data) {
    if (data['visits'] is! List) {
      throw const ApiException('تعذر قراءة قائمة الزيارات.');
    }
    return (data['visits'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
