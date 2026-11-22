import 'dart:async';

import 'api_client.dart';
import 'api_config.dart';
import 'network_status.dart';
import 'sync_service.dart';

/// Sends documents saved without internet and notices the server coming back
/// on devices without the POS screen (the Android sales-invoice shell), which
/// otherwise does this itself.
class AutomaticSync {
  AutomaticSync({
    NetworkStatusSource? network,
    this.interval = const Duration(seconds: 15),
  }) : _network = network ?? DeviceNetworkStatus();

  final NetworkStatusSource _network;
  final Duration interval;
  Timer? _timer;
  StreamSubscription<bool>? _changes;
  bool _available = true;
  Future<void>? _running;

  Future<void> start() async {
    _timer = Timer.periodic(interval, (_) => tick());
    try {
      _available = await _network.available;
      // No network at all: screens open from the saved copy without waiting.
      if (!_available) ApiClient.offline.value = true;
      _changes = _network.changes.listen(
        (available) {
          _available = available;
          if (!available) {
            ApiClient.offline.value = true;
          } else {
            unawaited(tick());
          }
        },
        onError: (Object _) {
          /* The periodic check still runs if OS events fail. */
        },
      );
    } catch (_) {
      /* Platforms without a network monitor rely on the periodic check. */
    }
    await tick();
  }

  /// Joins a check already in progress instead of starting a second one.
  Future<void> tick() =>
      _running ??= _check().whenComplete(() => _running = null);

  Future<void> _check() async {
    if (!_available ||
        ApiClient.token == null ||
        ApiClient.sessionExpired.value) {
      return;
    }
    try {
      await SyncService.synchronizeAutomatically();
      if (ApiClient.offline.value && !SyncService.busy.value) {
        // A small read; a successful answer marks the app online again.
        await ApiClient.get(
          Uri.parse('${ApiConfig.baseUrl}/theme'),
          timeout: const Duration(seconds: 8),
        );
      }
    } catch (_) {
      /* Still offline; the next tick tries again. */
    }
  }

  void dispose() {
    _timer?.cancel();
    _changes?.cancel();
  }
}
