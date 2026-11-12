import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'offline_store.dart';

class ApiClient {
  ApiClient._();

  static const _tokenKey = 'wasla_access_token';
  static const _sessionKey = 'wasla_user_session';
  static const _envelopeKey = 'wasla_session_v2';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static String? _token;
  static Map<String, dynamic>? _session;
  static final sessionExpired = ValueNotifier<bool>(false);
  static String? initializationError;
  static http.Client client = http.Client();
  static final offline = ValueNotifier<bool>(false);
  static final cachedAt = ValueNotifier<String?>(null);
  static Stopwatch? _connectionAge;
  static String? _connectionToken, _connectionBranch;

  static bool hasRecentConnection(Object? branchId) =>
      !offline.value &&
      !sessionExpired.value &&
      _token != null &&
      _connectionToken == _token &&
      _connectionBranch == '$branchId' &&
      _connectionAge != null &&
      _connectionAge!.elapsed < const Duration(seconds: 15);

  static OfflineStore? get offlineStore {
    final current = user;
    if (current?['id'] == null || current?['tenant_id'] == null) return null;
    return OfflineStore(
      [
        ApiConfig.baseUrl,
        current!['tenant_id'],
        current['id'],
        current['branch_id'],
      ].join('|'),
    );
  }

  static String? get token => _token;

  static Map<String, dynamic>? get session => _session;

  static Map<String, dynamic>? get user {
    final value = _session?['user'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static Map<String, dynamic>? get employee {
    final value = _session?['employee'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static Future<void> initialize() async {
    _connectionAge = null;
    _token = null;
    _session = null;
    initializationError = null;
    sessionExpired.value = false;
    offline.value = false;
    cachedAt.value = null;
    try {
      final envelope = await _storage.read(key: _envelopeKey);
      if (envelope != null) {
        final data = jsonDecode(envelope) as Map;
        if (data['token'] is! String || data['session'] is! Map) {
          throw const FormatException('Invalid session');
        }
        _token = data['token'];
        _session = Map<String, dynamic>.from(data['session']);
      } else {
        // Migrate the previous two-key representation on the next login.
        final savedToken = await _storage.read(key: _tokenKey);
        final savedSession = await _storage.read(key: _sessionKey);
        if (savedToken != null && savedSession != null) {
          final decoded = jsonDecode(savedSession);
          if (decoded is! Map) throw const FormatException('Invalid session');
          _token = savedToken;
          _session = Map<String, dynamic>.from(decoded);
        }
      }
      if (_token?.isEmpty == true || (_session != null && user == null)) {
        throw const FormatException('Invalid session');
      }
    } catch (_) {
      _token = null;
      _session = null;
      initializationError = 'تعذر استعادة الجلسة المحفوظة. سجّل الدخول مجدداً.';
    }
  }

  static Future<void> saveSession({
    required String token,
    required Map<String, dynamic> session,
  }) async {
    _connectionAge = null;
    if (token.isEmpty || session['user'] is! Map) {
      throw const FormatException('بيانات تسجيل الدخول غير صالحة');
    }
    final snapshot = Map<String, dynamic>.from(jsonDecode(jsonEncode(session)));
    await _storage.write(
      key: _envelopeKey,
      value: jsonEncode({'token': token, 'session': snapshot}),
    );
    _token = token;
    _session = snapshot;
    offline.value = false;
    cachedAt.value = null;
    initializationError = null;
    sessionExpired.value = false;
  }

  static Future<void> clearSession() async {
    _token = null;
    _session = null;
    sessionExpired.value = false;
    offline.value = false;
    cachedAt.value = null;
    await Future.wait([
      _storage.delete(key: _envelopeKey),
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _sessionKey),
    ]);
  }

  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool cacheForOffline = false,
    bool preferCache = false,
    Duration? timeout,
  }) async {
    final requestToken = token;
    final store = cacheForOffline ? offlineStore : null;
    final usable = store != null && !sessionExpired.value;
    // Read the snapshot only when it will be served; otherwise just check it
    // exists (choosing the timeout) without loading a whole catalog.
    final saved = usable && preferCache ? await store.cached(uri) : null;
    final hasSaved = saved != null || (usable && await store.hasCached(uri));
    final readTimeout =
        timeout ?? Duration(seconds: cacheForOffline && !hasSaved ? 60 : 20);
    if (preferCache && usable) {
      final snapshot = saved;
      if (snapshot != null) {
        offline.value = true;
        cachedAt.value = snapshot['saved_at'] as String?;
        return http.Response.bytes(
          utf8.encode(snapshot['body'] as String),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'x-wasla-offline': 'true',
          },
        );
      }
    }
    try {
      final response = await _observe(
        client
            .get(
              uri,
              headers: {
                ...?headers,
                ...await _headers(uri: uri),
              },
            )
            // A full catalog can take longer than a small connectivity probe.
            // Known-offline startup uses preferCache above without this wait.
            .timeout(readTimeout),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (requestToken != null &&
            token == requestToken &&
            uri.origin == Uri.parse(ApiConfig.baseUrl).origin &&
            response.headers['x-wasla-offline'] != 'true') {
          offline.value = false;
          _connectionToken = requestToken;
          _connectionBranch =
              uri.queryParameters['branch_id'] ??
              user?['branch_id']?.toString();
          _connectionAge = Stopwatch()..start();
        }
        if (store != null) {
          try {
            await store.cache(uri, utf8.decode(response.bodyBytes));
          } catch (_) {
            /* Online data remains usable if caching is unavailable. */
          }
        }
      } else if (token == requestToken) {
        _connectionAge = null;
      }
      // Permission errors and server errors must never become cached success.
      return response;
    } catch (error) {
      if (token == requestToken) _connectionAge = null;
      if (error is! http.ClientException && error is! TimeoutException) rethrow;
      if (store != null && !sessionExpired.value) {
        final snapshot = await store.cached(uri);
        if (snapshot != null) {
          offline.value = true;
          cachedAt.value = snapshot['saved_at'] as String?;
          return http.Response.bytes(
            utf8.encode(snapshot['body'] as String),
            200,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'x-wasla-offline': 'true',
            },
          );
        }
      }
      if (error is TimeoutException) {
        final resource = switch (uri.path.split('/').last) {
          'products' => 'الأصناف',
          'customers' => 'العملاء',
          'active' => 'الوردية',
          _ => 'البيانات',
        };
        throw TimeoutException(
          'لم يرد الخادم عند تحميل $resource خلال ${readTimeout.inSeconds} ثانية. '
          '${cacheForOffline ? 'لا تتوفر نسخة محلية لهذه البيانات على هذا الجهاز والحساب. ' : ''}'
          'تحقّق من الوصول إلى ${uri.host} وأعد المحاولة.',
          error.duration,
        );
      }
      rethrow;
    }
  }

  static Future<http.Response> post(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final requestToken = token;
    final requestHeaders = {
      ...?headers,
      ...await _headers(uri: uri, body: body, authenticated: authenticated),
    };
    try {
      final response = await _observe(
        client
            .post(
              uri,
              headers: requestHeaders,
              body: body == null || body is String
                  ? body as String?
                  : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 20)),
        authenticated: authenticated,
      );
      if (authenticated &&
          requestToken != null &&
          token == requestToken &&
          uri.origin == Uri.parse(ApiConfig.baseUrl).origin) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.headers['x-wasla-offline'] != 'true') {
          offline.value = false;
          _connectionToken = requestToken;
          _connectionBranch = requestHeaders['X-Branch-ID'];
          _connectionAge = Stopwatch()..start();
        } else {
          _connectionAge = null;
        }
      }
      return response;
    } catch (_) {
      if (authenticated && token == requestToken) _connectionAge = null;
      rethrow;
    }
  }

  static Future<http.Response> patch(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) async => _observe(
    client
        .patch(
          uri,
          headers: {
            ...?headers,
            ...await _headers(uri: uri, body: body),
          },
          body: body == null || body is String
              ? body as String?
              : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20)),
  );

  static Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
  }) async => _observe(
    client
        .delete(
          uri,
          headers: {
            ...?headers,
            ...await _headers(uri: uri),
          },
        )
        .timeout(const Duration(seconds: 20)),
  );

  static Future<http.Response> _observe(
    Future<http.Response> request, {
    bool authenticated = true,
  }) async {
    final response = await request;
    if (authenticated && response.statusCode == 401 && _token != null) {
      sessionExpired.value = true;
    }
    return response; // Never retry a financial write automatically.
  }

  static Future<Map<String, String>> _headers({
    required Uri uri,
    Object? body,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final tenantId = user?['tenant_id']?.toString();
    dynamic decodedBody = body;
    if (body is String) {
      try {
        decodedBody = jsonDecode(body);
      } catch (_) {}
    }
    final bodyMap = decodedBody is Map
        ? decodedBody
        : const <String, dynamic>{};
    final branchId =
        bodyMap['branch_id']?.toString() ??
        uri.queryParameters['branch_id'] ??
        user?['branch_id']?.toString();
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['X-Tenant-ID'] = tenantId;
    }
    if (branchId != null && branchId.isNotEmpty && branchId != 'null') {
      headers['X-Branch-ID'] = branchId;
    }
    if (authenticated && _token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }
}
