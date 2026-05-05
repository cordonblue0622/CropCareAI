import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity and exposes a broadcast stream.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  Stream<bool> get onConnectivityChanged => _controller.stream;

  ConnectivityService() {
    _connectivity.onConnectivityChanged.listen((results) {
      _controller.add(_hasConnection(results));
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  void dispose() => _controller.close();
}
