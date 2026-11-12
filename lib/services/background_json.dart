import 'dart:convert';
import 'dart:isolate';

/// Parses large JSON bodies (full catalogs, customer lists) off the UI thread,
/// so scanning and scrolling stay smooth while data loads on slow devices.
abstract final class BackgroundJson {
  /// Widget tests run on a fake clock that never delivers isolate results;
  /// they turn this off to parse inline.
  static bool enabled = true;

  static const _threshold = 64 * 1024;

  static Future<dynamic> decodeBytes(List<int> bytes) {
    if (!enabled || bytes.length < _threshold) {
      return Future.value(jsonDecode(utf8.decode(bytes)));
    }
    return Isolate.run(() => jsonDecode(utf8.decode(bytes)));
  }

  static Future<dynamic> decode(String body) {
    if (!enabled || body.length < _threshold) {
      return Future.value(jsonDecode(body));
    }
    return Isolate.run(() => jsonDecode(body));
  }
}
