import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/mqtt_config.dart';
import '../models/mqtt_event.dart';

class MqttService {
  MqttService();

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSubscription;

  final StreamController<MqttEvent> _events = StreamController<MqttEvent>.broadcast();
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  Stream<MqttEvent> get events => _events.stream;
  Stream<bool> get connectionStream => _connection.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  int? get brokerPingLatencyMs => _client?.lastCycleLatency;

  String _newClientId() {
    final random = Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    return 'AGRO_MOB_${stamp}_$random';
  }

  Future<void> connect() async {
    if (isConnected) return;

    // If an established client is temporarily disconnected, let its built-in
    // auto-reconnect recover the session instead of creating a duplicate client.
    if (_client != null) {
      _client!.doAutoReconnect(force: true);
      return;
    }

    await _updatesSubscription?.cancel();
    _updatesSubscription = null;

    final client = MqttServerClient.withPort(
      MqttConfig.broker,
      _newClientId(),
      MqttConfig.port,
    );

    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.connectTimeoutPeriod = 8000;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.setProtocolV311();

    client.onConnected = () {
      if (!_connection.isClosed) _connection.add(true);
    };

    client.onDisconnected = () {
      if (!_connection.isClosed) _connection.add(false);
    };

    client.onAutoReconnect = () {
      if (!_connection.isClosed) _connection.add(false);
    };

    client.onAutoReconnected = () {
      if (!_connection.isClosed) _connection.add(true);
    };

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(client.clientIdentifier)
        .startClean();

    _client = client;

    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
      _client = null;
      if (!_connection.isClosed) _connection.add(false);
      rethrow;
    }

    if (!isConnected) {
      client.disconnect();
      _client = null;
      throw StateError('MQTT broker connection failed: ${client.connectionStatus}');
    }

    _updatesSubscription = client.updates?.listen(_onMessages);
    _subscribeAll();
    if (!_connection.isClosed) _connection.add(true);
  }

  void _subscribeAll() {
    final client = _client;
    if (client == null || !isConnected) return;

    client.subscribe(MqttConfig.telemetryTopic, MqttQos.atMostOnce);
    client.subscribe(MqttConfig.stateTopic, MqttQos.atLeastOnce);
    client.subscribe(MqttConfig.statusTopic, MqttQos.atLeastOnce);
    client.subscribe(MqttConfig.desiredTopic, MqttQos.atLeastOnce);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final message = received.payload;
      if (message is! MqttPublishMessage) continue;

      final text = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );

      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          _events.add(
            MqttEvent(
              topic: received.topic,
              payload: Map<String, dynamic>.from(decoded),
            ),
          );
        }
      } catch (_) {
        // Ignore malformed public-broker traffic that does not match our JSON contract.
      }
    }
  }

  void publishDesired(Map<String, dynamic> payload) {
    final client = _client;
    if (client == null || !isConnected) {
      throw StateError('MQTT broker is not connected');
    }

    final builder = MqttClientPayloadBuilder()..addString(jsonEncode(payload));
    final bytes = builder.payload;
    if (bytes == null) return;

    client.publishMessage(
      MqttConfig.desiredTopic,
      MqttQos.atLeastOnce,
      bytes,
      retain: true,
    );
  }

  Future<void> reconnect() async {
    final client = _client;
    if (client != null) {
      try {
        client.disconnect();
      } catch (_) {}
    }
    _client = null;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await connect();
  }

  Future<void> disconnect() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    if (!_connection.isClosed) _connection.add(false);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _connection.close();
  }
}
