import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/mqtt_config.dart';
import '../models/network_state.dart';

class NetworkService {
  NetworkService();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final StreamController<NetworkState> _controller =
      StreamController<NetworkState>.broadcast();

  Stream<NetworkState> get stream => _controller.stream;

  Future<NetworkState> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    final state = await _buildState(results);
    if (!_controller.isClosed) _controller.add(state);
    return state;
  }

  Future<void> start() async {
    await checkNow();
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      final state = await _buildState(results);
      if (!_controller.isClosed) _controller.add(state);
    });
  }

  Future<NetworkState> _buildState(List<ConnectivityResult> results) async {
    final hasInterface = !results.contains(ConnectivityResult.none) && results.isNotEmpty;
    final transport = _mapTransport(results);
    var reachable = false;

    if (hasInterface) {
      try {
        final socket = await Socket.connect(
          MqttConfig.broker,
          MqttConfig.port,
          timeout: const Duration(seconds: 2),
        );
        reachable = true;
        socket.destroy();
      } catch (_) {
        reachable = false;
      }
    }

    return NetworkState(
      transport: transport,
      hasInterface: hasInterface,
      internetReachable: reachable,
      lastChecked: DateTime.now(),
    );
  }

  NetworkTransport _mapTransport(List<ConnectivityResult> values) {
    if (values.contains(ConnectivityResult.wifi)) return NetworkTransport.wifi;
    if (values.contains(ConnectivityResult.mobile)) return NetworkTransport.mobile;
    if (values.contains(ConnectivityResult.ethernet)) return NetworkTransport.ethernet;
    if (values.contains(ConnectivityResult.vpn)) return NetworkTransport.vpn;
    if (values.contains(ConnectivityResult.satellite)) return NetworkTransport.satellite;
    if (values.contains(ConnectivityResult.bluetooth)) return NetworkTransport.bluetooth;
    if (values.contains(ConnectivityResult.other)) return NetworkTransport.other;
    return NetworkTransport.none;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
