/// Shared API location. Defaults to the hosted WaslaPOS API.
/// Override with --dart-define=API_BASE_URL=https://host/api when needed.
abstract final class ApiConfig {
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceAll(RegExp(r'/+$'), '');
    }
    return 'https://waslapos.app/api';
  }
}
