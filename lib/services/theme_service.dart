import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

import 'api_config.dart';

class ThemeService {
  Future<String> fetchTheme(int? tenantId) async {
    if (tenantId == null || tenantId <= 0) return 'blue';

    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/theme')
            .replace(queryParameters: {'tenant_id': tenantId.toString()}),
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) return 'blue';
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final name = data['theme']?['name']?.toString();
      return const {'blue', 'orange', 'green'}.contains(name) ? name! : 'blue';
    } catch (error) {
      debugPrint('Unable to load store theme: $error');
      return 'blue';
    }
  }
}
