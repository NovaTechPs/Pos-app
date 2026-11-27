import 'api_client.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// The web «مركز التقارير» through the API: the same reports, filters and totals.
class ReportCenterService {
  const ReportCenterService();

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${ApiConfig.baseUrl}/reports$path',
  ).replace(queryParameters: query == null || query.isEmpty ? null : query);

  /// Groups of reports this user may open, the branches, and whether profit is visible.
  Future<Map<String, dynamic>> index() async =>
      ApiException.decode(await ApiClient.get(_uri('')));

  /// One page of [report] for [filters] (see [ReportFilters.query]).
  Future<Map<String, dynamic>> show(
    String report,
    Map<String, String> filters, {
    int page = 1,
  }) async => ApiException.decode(
    await ApiClient.get(
      _uri('/${Uri.encodeComponent(report)}', {
        ...filters,
        if (page > 1) 'page': '$page',
      }),
    ),
  );

  Future<List<Map<String, dynamic>>> parties(
    String search, {
    String type = 'all',
  }) async {
    final data = ApiException.decode(
      await ApiClient.get(
        _uri('/parties', {
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'type': type,
        }),
      ),
    );
    return _list(data['parties']);
  }

  Future<List<Map<String, dynamic>>> products(String search) async {
    if (search.trim().isEmpty) return const [];
    final data = ApiException.decode(
      await ApiClient.get(_uri('/products', {'search': search.trim()})),
    );
    return _list(data['products']);
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];
}
