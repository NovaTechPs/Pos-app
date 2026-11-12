import 'dart:convert';

import 'api_client.dart';
import 'api_config.dart';

class BranchService {
  Future<List<Map<String, dynamic>>> fetchBranches() async {
    final response = await ApiClient.get(
      Uri.parse('${ApiConfig.baseUrl}/branches'),
    );
    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل الفروع (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    final rows = data is List ? data : (data is Map ? data['branches'] : null);
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
