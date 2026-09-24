import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/mqtt_config.dart';
import '../models/control_state.dart';
import '../models/mqtt_event.dart';
import '../models/network_state.dart';
import '../models/telemetry.dart';
import '../services/history_store.dart';
import '../services/mqtt_service.dart';
import '../services/network_service.dart';

class AgroController extends ChangeNotifier {
  AgroController({
    MqttService? mqttService,
    NetworkService? networkService,
    HistoryStore? historyStore,
  })  : _mqtt = mqttService ?? MqttService(),
        _networkService = networkService ?? NetworkService(),
        _historyStore = historyStore ?? HistoryStore();

  final MqttService _mqtt;
  final NetworkService _networkService;
  final HistoryStore _historyStore;

  StreamSubscription<MqttEvent>? _mqttEventsSub;
  StreamSubscription<bool>? _mqttConnectionSub;
  StreamSubscription<NetworkState>? _networkSub;

  Timer? _freshnessTimer;
  Timer? _networkProbeTimer;
  Timer? _historySaveTimer;

  final Map<String, int> _commandSentMicros = <String, int>{};
  final Map<String, Timer> _commandTimeouts = <String, Timer>{};

  Telemetry _telemetry = Telemetry.empty();
  Telemetry get telemetry => _telemetry;

  ControlState _controls = const ControlState();
  ControlState get controls => _controls;

  NetworkState _network = const NetworkState();
  NetworkState get network => _network;

  final List<Telemetry> _history = <Telemetry>[];
  List<Telemetry> get history => List<Telemetry>.unmodifiable(_history);

  bool _mqttConnected = false;
  bool get mqttConnected => _mqttConnected;

  bool _deviceReportedOnline = false;
  bool get deviceReportedOnline => _deviceReportedOnline;

  DateTime? _lastSeen;
  DateTime? get lastSeen => _lastSeen;

  String? _error;
  String? get error => _error;

  bool _initialized = false;
  bool _connectInProgress = false;
  bool get initialized => _initialized;

  int get brokerPingLatencyMs => _mqtt.brokerPingLatencyMs ?? 0;

  bool get internetReachable => _network.internetReachable;

  bool get deviceOnline {
    final seen = _lastSeen;
    if (!_mqttConnected || seen == null) return false;
    return DateTime.now().difference(seen) < MqttConfig.staleAfter;
  }

  Duration? get packetAge {
    final seen = _lastSeen;
    if (seen == null) return null;
    return DateTime.now().difference(seen);
  }

  String get farmHealthText {
    if (!deviceOnline) return 'Waiting for live device telemetry';
    if (_telemetry.waterLevel < 15) return 'Water tank is critically low';
    if (_telemetry.soil < 30) return 'Soil is dry — automatic irrigation output is active';
    if (_telemetry.soil < 45) return 'Soil moisture is slightly low';
    if (_telemetry.temperature > 38) return 'Field temperature is high';
    return 'Field conditions are stable';
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _history
      ..clear()
      ..addAll(await _historyStore.load());

    _mqttEventsSub = _mqtt.events.listen(_handleMqttEvent);
    _mqttConnectionSub = _mqtt.connectionStream.listen((connected) {
      _mqttConnected = connected;
      if (!connected) {
        _deviceReportedOnline = false;
      }
      notifyListeners();
    });

    _networkSub = _networkService.stream.listen((state) async {
      final wasReachable = _network.internetReachable;
      _network = state;
      notifyListeners();

      if (!wasReachable && state.internetReachable && !_mqttConnected) {
        await connectMqtt();
      }
    });

    await _networkService.start();

    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });

    _networkProbeTimer = Timer.periodic(MqttConfig.networkProbeInterval, (_) {
      _networkService.checkNow();
    });

    _initialized = true;
    notifyListeners();

    if (_network.internetReachable) {
      await connectMqtt();
    }
  }

  Future<void> connectMqtt() async {
    if (_connectInProgress || _mqttConnected) return;
    _connectInProgress = true;
    _error = null;
    notifyListeners();

    try {
      await _mqtt.connect();
      _mqttConnected = _mqtt.isConnected;
      _error = null;
    } catch (error) {
      _mqttConnected = false;
      _error = 'MQTT connection failed: $error';
    } finally {
      _connectInProgress = false;
    }

    notifyListeners();
  }

  Future<void> reconnectMqtt() async {
    _error = null;
    notifyListeners();

    try {
      await _mqtt.reconnect();
      _mqttConnected = _mqtt.isConnected;
    } catch (error) {
      _error = 'Reconnect failed: $error';
    }

    notifyListeners();
  }

  Future<void> refreshNetwork() async {
    await _networkService.checkNow();
  }

  Future<void> onAppResumed() async {
    await refreshNetwork();
    if (_network.internetReachable && !_mqttConnected) {
      await connectMqtt();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _handleMqttEvent(MqttEvent event) {
    if (event.topic == MqttConfig.telemetryTopic) {
      _handleTelemetry(event.payload);
      return;
    }

    if (event.topic == MqttConfig.stateTopic) {
      _handleState(event.payload);
      return;
    }

    if (event.topic == MqttConfig.desiredTopic) {
      _handleDesired(event.payload);
      return;
    }

    if (event.topic == MqttConfig.statusTopic) {
      _deviceReportedOnline = _asBool(event.payload['online']);
      notifyListeners();
    }
  }

  void _handleTelemetry(Map<String, dynamic> payload) {
    final now = DateTime.now();
    _telemetry = Telemetry.fromMap(payload, receivedAt: now);
    _lastSeen = now;
    _deviceReportedOnline = true;

    _controls = _controls.copyWith(
      actual1: _telemetry.led1,
      actual2: _telemetry.led2,
      actual3: _telemetry.led3,
      actual4: _telemetry.led4,
    );

    if (_history.isEmpty ||
        now.difference(_history.last.receivedAt) >= const Duration(seconds: 1)) {
      _history.add(_telemetry);
      if (_history.length > MqttConfig.maxHistoryPoints) {
        _history.removeRange(0, _history.length - MqttConfig.maxHistoryPoints);
      }
      _scheduleHistorySave();
    }

    notifyListeners();
  }

  void _handleState(Map<String, dynamic> payload) {
    _controls = _controls.copyWith(
      actual1: _asBool(payload['led1']),
      actual2: _asBool(payload['led2']),
      actual3: _asBool(payload['led3']),
      actual4: _asBool(payload['led4']),
    );

    final commandId = payload['ackCommandId']?.toString() ?? '';
    if (commandId.isNotEmpty) {
      final sentAt = _commandSentMicros.remove(commandId);
      _commandTimeouts.remove(commandId)?.cancel();

      if (sentAt != null) {
        final roundTrip =
            ((DateTime.now().microsecondsSinceEpoch - sentAt) / 1000).round();
        _controls = _controls.copyWith(
          clearPending: true,
          lastRoundTripMs: roundTrip,
          lastCommandId: commandId,
        );
      }
    }

    notifyListeners();
  }

  void _handleDesired(Map<String, dynamic> payload) {
    _controls = _controls.copyWith(
      desired2: _asBool(payload['led2']),
      desired3: _asBool(payload['led3']),
      desired4: _asBool(payload['led4']),
    );
    notifyListeners();
  }

  Future<void> setMotor(int motor, bool value) async {
    if (!_mqttConnected) {
      _error = 'MQTT broker is disconnected';
      notifyListeners();
      return;
    }

    if (!deviceOnline) {
      _error = 'ESP32 is offline. Start the device before sending motor commands.';
      notifyListeners();
      return;
    }

    var desired2 = _controls.desired2;
    var desired3 = _controls.desired3;
    var desired4 = _controls.desired4;

    switch (motor) {
      case 1:
        desired2 = value;
        break;
      case 2:
        desired3 = value;
        break;
      case 3:
        desired4 = value;
        break;
      default:
        return;
    }

    final key = 'motor$motor';
    final commandId =
        '${DateTime.now().millisecondsSinceEpoch}_${motor}_${DateTime.now().microsecond}';

    _controls = _controls.copyWith(
      desired2: desired2,
      desired3: desired3,
      desired4: desired4,
      pendingKey: key,
    );
    _error = null;

    _commandSentMicros[commandId] = DateTime.now().microsecondsSinceEpoch;

    _commandTimeouts[commandId]?.cancel();
    _commandTimeouts[commandId] = Timer(MqttConfig.commandTimeout, () {
      if (_commandSentMicros.remove(commandId) != null) {
        _controls = _controls.copyWith(clearPending: true);
        _error = 'ESP32 command acknowledgement timed out';
        notifyListeners();
      }
    });

    notifyListeners();

    try {
      _mqtt.publishDesired({
        'commandId': commandId,
        'led2': desired2,
        'led3': desired3,
        'led4': desired4,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
        'source': 'flutter-mobile',
      });
    } catch (error) {
      _commandSentMicros.remove(commandId);
      _commandTimeouts.remove(commandId)?.cancel();
      _controls = _controls.copyWith(clearPending: true);
      _error = 'Command publish failed: $error';
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    _historySaveTimer?.cancel();
    await _historyStore.clear();
    notifyListeners();
  }

  void _scheduleHistorySave() {
    _historySaveTimer?.cancel();
    _historySaveTimer = Timer(const Duration(seconds: 3), () {
      _historyStore.save(_history);
    });
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true';
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _networkProbeTimer?.cancel();
    _historySaveTimer?.cancel();
    for (final timer in _commandTimeouts.values) {
      timer.cancel();
    }
    _commandTimeouts.clear();
    _mqttEventsSub?.cancel();
    _mqttConnectionSub?.cancel();
    _networkSub?.cancel();
    _historyStore.save(_history);
    _mqtt.dispose();
    _networkService.dispose();
    super.dispose();
  }
}
