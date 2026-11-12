import 'package:connectivity_plus/connectivity_plus.dart';

/// A network interface is a hint; API requests still verify server reachability.
abstract interface class NetworkStatusSource {
  Future<bool> get available;
  Stream<bool> get changes;
}

class DeviceNetworkStatus implements NetworkStatusSource {
  final _connectivity = Connectivity();

  @override
  Future<bool> get available async => (await _connectivity.checkConnectivity())
      .any((value) => value != ConnectivityResult.none);

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged
      .map((values) => values.any((value) => value != ConnectivityResult.none))
      .distinct();
}
