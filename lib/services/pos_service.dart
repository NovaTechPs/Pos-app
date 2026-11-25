import 'api_config.dart';

import 'api_client.dart';
import 'api_exception.dart';

class PosService {
  bool supportsGiftLines = false;

  /// False only when the server says this cashier may not sell under cost (`pos.sell_below_cost`);
  /// an older server that does not say keeps the earlier behaviour.
  bool canSellBelowCost = true;
  bool lastFetchOffline = false;
  bool supportsOfflineSales = false;
  Uri? _freshCatalogUri;
  String? _freshCatalogBody;
  String? _freshCatalogToken;
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> fetchInvoice(
    int branchId, {
    int? before,
    int? after,
    String? search,
  }) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/pos/invoices').replace(
        queryParameters: {
          'branch_id': '$branchId',
          if (before != null) 'before': '$before',
          if (after != null) 'after': '$after',
          'search': ?search,
        },
      ),
      cacheForOffline: true,
    );
    final data = await ApiException.decodeAsync(response);
    if (data['order'] is! Map) {
      throw const ApiException('لا توجد فاتورة مطابقة.');
    }
    return Map<String, dynamic>.from(data['order']);
  }

  Future<void> deleteInvoice(int id) async {
    if (ApiClient.offline.value) {
      throw const ApiException('اتصل بالخادم لحذف فاتورة محفوظة.');
    }
    final response = await ApiClient.delete(
      Uri.parse('$baseUrl/pos/invoices/$id'),
    );
    ApiException.decode(response);
  }

  Future<List<dynamic>> fetchCategories(
    int branchId, {
    int? customerId,
    bool preferCache = false,
    int? pricingBranchId,
  }) async {
    _freshCatalogUri = null;
    _freshCatalogBody = null;
    final token = ApiClient.token;
    final query = {'branch_id': '$branchId'};
    if (customerId != null) query['customer_id'] = '$customerId';
    final uri = Uri.parse('$baseUrl/pos/products')
        .replace(queryParameters: query);
    if ((preferCache || ApiClient.offline.value) &&
        customerId != null &&
        pricingBranchId != null) {
      final store = ApiClient.offlineStore;
      final exact = await store?.cached(uri);
      if (exact == null) {
        final shared = await store?.cached(
          _pricingSnapshot(branchId, pricingBranchId),
        );
        if (shared != null && store != null) {
          await store.cache(uri, shared['body'] as String);
        }
      }
    }
    final response = await ApiClient.get(
      uri,
      cacheForOffline: true,
      preferCache: preferCache,
    );
    final data = await ApiException.decodeAsync(response);
    lastFetchOffline = response.headers['x-wasla-offline'] == 'true';
    supportsOfflineSales = data['offline_contract_version'] == 1;
    supportsGiftLines = data['pos_line_contract_version'] == 2;
    canSellBelowCost = data['can_sell_below_cost'] != false;
    if (data['categories'] is! List) {
      throw const ApiException('تعذر قراءة قائمة الأصناف.');
    }
    if (!lastFetchOffline && token == ApiClient.token) {
      _freshCatalogUri = uri;
      _freshCatalogBody = response.body;
      _freshCatalogToken = token;
    }
    return data['categories'];
  }

  Uri _pricingSnapshot(int branchId, int pricingBranchId) =>
      Uri.parse('$baseUrl/pos/offline-pricing').replace(
        queryParameters: {
          'branch_id': '$branchId',
          'pricing_branch_id': '$pricingBranchId',
        },
      );

  Future<void> prepareOfflineCustomerPricing(
    int branchId,
    List<dynamic> customers,
  ) async {
    final token = ApiClient.token;
    final store = ApiClient.offlineStore;
    if (store == null || token == null) return;
    final representatives = <int, int?>{branchId: null};
    for (final customer in customers) {
      final pricingBranch =
          int.tryParse('${customer['branch_id']}') ?? branchId;
      representatives.putIfAbsent(
        pricingBranch,
        () => int.tryParse('${customer['id']}'),
      );
    }
    for (final entry in representatives.entries) {
      if (ApiClient.token != token || ApiClient.sessionExpired.value) return;
      try {
        final query = {
          'branch_id': '$branchId',
          if (entry.value != null) 'customer_id': '${entry.value}',
        };
        final uri = Uri.parse('$baseUrl/pos/products')
            .replace(queryParameters: query);
        if (!lastFetchOffline &&
            _freshCatalogToken == token &&
            _freshCatalogUri == uri &&
            _freshCatalogBody != null) {
          await store.cache(
            _pricingSnapshot(branchId, entry.key),
            _freshCatalogBody!,
          );
          _freshCatalogBody = null;
          _freshCatalogUri = null;
          continue;
        }
        final response = await ApiClient.get(uri, cacheForOffline: true);
        if (response.statusCode == 200 &&
            response.headers['x-wasla-offline'] != 'true' &&
            (await ApiException.decodeAsync(response))['categories'] is List &&
            ApiClient.token == token) {
          await store.cache(
            _pricingSnapshot(branchId, entry.key),
            response.body,
          );
        }
      } catch (_) {
        /* Other pricing branches can still be used. */
      }
    }
  }

  Future<List<dynamic>> fetchHeld(int branchId) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/pos/held?branch_id=$branchId'),
      cacheForOffline: true,
      preferCache: ApiClient.offline.value,
    );
    final data = await ApiException.decodeAsync(response);
    if (data['orders'] is! List) {
      throw const ApiException('تعذر قراءة الفواتير المعلقة.');
    }
    return data['orders'];
  }
}
