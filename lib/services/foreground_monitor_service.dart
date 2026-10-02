import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/mqtt_config.dart';

class ForegroundPreferenceKeys {
  ForegroundPreferenceKeys._();

  static const enabled = 'fg.enabled';
  static const showDevice = 'fg.showDevice';
  static const showTemperature = 'fg.showTemperature';
  static const showHumidity = 'fg.showHumidity';
  static const showSoil = 'fg.showSoil';
  static const showWater = 'fg.showWater';
  static const showMotors = 'fg.showMotors';
  static const scheduleAlerts = 'fg.scheduleAlerts';
}

class ForegroundMonitorService {
  ForegroundMonitorService._();

  static const int serviceId = 8214;
  static const String iconMetaDataName = 'com.agroconnect.service.STATUS_ICON';

  static void initializePlugin() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'agro_live_status',
        channelName: 'Live farm status',
        channelDescription: 'Keeps the selected farm status visible while background monitoring is enabled.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<bool> requestNotificationPermission() async {
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.granted) return true;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  static Future<void> savePreferences(Map<String, bool> values) async {
    for (final entry in values.entries) {
      await FlutterForegroundTask.saveData(key: entry.key, value: entry.value);
    }
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'preferences',
        ...values,
      });
    }
  }

  static Future<Map<String, bool>> readPreferences() async {
    bool read(String key, bool fallback) {
      return fallback;
    }

    final all = await FlutterForegroundTask.getAllData();
    bool value(String key, bool fallback) {
      final raw = all[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      if (raw is String) return raw.toLowerCase() == 'true';
      return read(key, fallback);
    }

    return <String, bool>{
      ForegroundPreferenceKeys.enabled: value(ForegroundPreferenceKeys.enabled, false),
      ForegroundPreferenceKeys.showDevice: value(ForegroundPreferenceKeys.showDevice, true),
      ForegroundPreferenceKeys.showTemperature: value(ForegroundPreferenceKeys.showTemperature, true),
      ForegroundPreferenceKeys.showHumidity: value(ForegroundPreferenceKeys.showHumidity, true),
      ForegroundPreferenceKeys.showSoil: value(ForegroundPreferenceKeys.showSoil, true),
      ForegroundPreferenceKeys.showWater: value(ForegroundPreferenceKeys.showWater, true),
      ForegroundPreferenceKeys.showMotors: value(ForegroundPreferenceKeys.showMotors, false),
      ForegroundPreferenceKeys.scheduleAlerts: value(ForegroundPreferenceKeys.scheduleAlerts, true),
    };
  }

  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return await FlutterForegroundTask.isRunningService;
    }

    await FlutterForegroundTask.startService(
      serviceId: serviceId,
      serviceTypes: const <ForegroundServiceTypes>[
        ForegroundServiceTypes.specialUse,
      ],
      notificationTitle: 'AGRO CONNECT • Live Monitor',
      notificationText: 'Connecting to your farm…',
      notificationIcon: const NotificationIcon(
        metaDataName: iconMetaDataName,
        backgroundColor: Color(0xFF0F8F5F),
      ),
      notificationInitialRoute: '/',
      callback: agroForegroundStartCallback,
    );

    return await FlutterForegroundTask.isRunningService;
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void agroForegroundStartCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(AgroForegroundTaskHandler());
}

class AgroForegroundTaskHandler extends TaskHandler {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSubscription;
  bool _connecting = false;
  bool _mqttConnected = false;
  bool _deviceReportedOnline = false;
  DateTime? _lastTelemetryAt;
  DateTime? _lastNotificationUpdate;
  Map<String, dynamic> _telemetry = <String, dynamic>{};
  final Map<String, bool> _desired = <String, bool>{};

  bool _showDevice = true;
  bool _showTemperature = true;
  bool _showHumidity = true;
  bool _showSoil = true;
  bool _showWater = true;
  bool _showMotors = false;
  bool _scheduleAlerts = true;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _localNotificationsReady = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadPreferences();
    await _initializeLocalNotifications();
    await _connectMqtt();
    await _updatePersistentNotification(force: true);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_isConnected) {
      unawaited(_connectMqtt());
    }

    final last = _lastTelemetryAt;
    if (last != null && DateTime.now().difference(last) > MqttConfig.staleAfter) {
      _deviceReportedOnline = false;
    }
    unawaited(_updatePersistentNotification(force: false));
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    if (map['type'] != 'preferences') return;

    _showDevice = _bool(map[ForegroundPreferenceKeys.showDevice], _showDevice);
    _showTemperature = _bool(map[ForegroundPreferenceKeys.showTemperature], _showTemperature);
    _showHumidity = _bool(map[ForegroundPreferenceKeys.showHumidity], _showHumidity);
    _showSoil = _bool(map[ForegroundPreferenceKeys.showSoil], _showSoil);
    _showWater = _bool(map[ForegroundPreferenceKeys.showWater], _showWater);
    _showMotors = _bool(map[ForegroundPreferenceKeys.showMotors], _showMotors);
    _scheduleAlerts = _bool(map[ForegroundPreferenceKeys.scheduleAlerts], _scheduleAlerts);
    unawaited(_updatePersistentNotification(force: true));
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // Android 14+ may let users swipe an ongoing foreground-service notification.
    // Monitoring remains active; repost it because this feature is explicitly
    // user-enabled and is disabled from inside AGRO CONNECT settings.
    unawaited(_updatePersistentNotification(force: true));
  }

  bool get _isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> _loadPreferences() async {
    final all = await FlutterForegroundTask.getAllData();
    _showDevice = _bool(all[ForegroundPreferenceKeys.showDevice], true);
    _showTemperature = _bool(all[ForegroundPreferenceKeys.showTemperature], true);
    _showHumidity = _bool(all[ForegroundPreferenceKeys.showHumidity], true);
    _showSoil = _bool(all[ForegroundPreferenceKeys.showSoil], true);
    _showWater = _bool(all[ForegroundPreferenceKeys.showWater], true);
    _showMotors = _bool(all[ForegroundPreferenceKeys.showMotors], false);
    _scheduleAlerts = _bool(all[ForegroundPreferenceKeys.scheduleAlerts], true);
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_agro'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(settings);
    _localNotificationsReady = true;
  }

  String _newClientId() {
    final random = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    return 'AGRO_FG_${stamp}_$random';
  }

  Future<void> _connectMqtt() async {
    if (_connecting || _isConnected) return;
    _connecting = true;

    try {
      await _updatesSubscription?.cancel();
      _updatesSubscription = null;
      try {
        _client?.disconnect();
      } catch (_) {}

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
        _mqttConnected = true;
        unawaited(_updatePersistentNotification(force: true));
      };
      client.onDisconnected = () {
        _mqttConnected = false;
        unawaited(_updatePersistentNotification(force: true));
      };
      client.onAutoReconnect = () {
        _mqttConnected = false;
        unawaited(_updatePersistentNotification(force: true));
      };
      client.onAutoReconnected = () {
        _mqttConnected = true;
        unawaited(_updatePersistentNotification(force: true));
      };

      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(client.clientIdentifier)
          .startClean();

      _client = client;
      await client.connect();

      if (!_isConnected) {
        throw StateError('MQTT foreground connection failed');
      }

      _mqttConnected = true;
      client.subscribe(MqttConfig.telemetryTopic, MqttQos.atMostOnce);
      client.subscribe(MqttConfig.statusTopic, MqttQos.atLeastOnce);
      client.subscribe(MqttConfig.desiredTopic, MqttQos.atLeastOnce);
      client.subscribe(MqttConfig.stateTopic, MqttQos.atLeastOnce);
      _updatesSubscription = client.updates?.listen(_onMessages);
    } catch (_) {
      _mqttConnected = false;
      try {
        _client?.disconnect();
      } catch (_) {}
      _client = null;
    } finally {
      _connecting = false;
      await _updatePersistentNotification(force: true);
    }
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final message = received.payload;
      if (message is! MqttPublishMessage) continue;

      final text = MqttPublishPayload.bytesToStringAsString(message.payload.message);
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) continue;
        payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }

      if (received.topic == MqttConfig.telemetryTopic) {
        _telemetry = payload;
        _lastTelemetryAt = DateTime.now();
        _deviceReportedOnline = true;
        unawaited(_updatePersistentNotification(force: false));
      } else if (received.topic == MqttConfig.statusTopic) {
        _deviceReportedOnline = _bool(payload['online'], _deviceReportedOnline);
        unawaited(_updatePersistentNotification(force: true));
      } else if (received.topic == MqttConfig.desiredTopic) {
        unawaited(_handleDesired(payload));
      } else if (received.topic == MqttConfig.stateTopic) {
        // State is useful when the device publishes motor state more frequently
        // than telemetry. Merge only the output fields we care about.
        for (final key in const ['led2', 'led3', 'led4']) {
          if (payload.containsKey(key)) _telemetry[key] = payload[key];
        }
        unawaited(_updatePersistentNotification(force: false));
      }
    }
  }

  Future<void> _handleDesired(Map<String, dynamic> payload) async {
    final previous = Map<String, bool>.from(_desired);
    for (final key in const ['led2', 'led3', 'led4']) {
      if (payload.containsKey(key)) {
        _desired[key] = _bool(payload[key], false);
      }
    }

    if (!_scheduleAlerts) return;

    final source = (payload['source'] ?? '').toString().toLowerCase();
    final commandId = (payload['commandId'] ?? '').toString().toLowerCase();
    final isSchedule = source.contains('schedule') || commandId.contains('schedule');
    if (!isSchedule) return;

    final sentAtRaw = payload['sentAt'];
    final sentAt = sentAtRaw is num ? sentAtRaw.toInt() : int.tryParse('$sentAtRaw');
    if (sentAt != null) {
      final age = DateTime.now().millisecondsSinceEpoch - sentAt;
      if (age < -30000 || age > 120000) return; // ignore stale retained commands
    }

    final changes = <String>[];
    for (var motor = 1; motor <= 3; motor++) {
      final key = 'led${motor + 1}';
      if (!payload.containsKey(key)) continue;
      final next = _bool(payload[key], false);
      final before = previous[key];
      if (before == null) {
        if (next) changes.add('Motor $motor started');
      } else if (before != next) {
        changes.add(next ? 'Motor $motor started' : 'Motor $motor completed');
      }
    }

    if (changes.isEmpty) return;
    await _showScheduleAlert(changes.join(' • '));
  }

  Future<void> _showScheduleAlert(String message) async {
    await _initializeLocalNotifications();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'agro_plan_activity',
        'Plan activity',
        channelDescription: 'Alerts when a planned motor run starts or finishes.',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_agro',
        autoCancel: true,
        ongoing: false,
        onlyAlertOnce: false,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final id = DateTime.now().millisecondsSinceEpoch.remainder(2000000000);
    await _localNotifications.show(
      id,
      'AGRO CONNECT • Plan',
      message,
      details,
      payload: 'plan',
    );
  }

  Future<void> _updatePersistentNotification({required bool force}) async {
    final now = DateTime.now();
    if (!force && _lastNotificationUpdate != null &&
        now.difference(_lastNotificationUpdate!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastNotificationUpdate = now;

    final online = _mqttConnected &&
        _deviceReportedOnline &&
        _lastTelemetryAt != null &&
        now.difference(_lastTelemetryAt!) < MqttConfig.staleAfter;

    final items = <String>[];
    if (_showDevice) items.add(online ? 'Online' : 'Offline');
    if (_showTemperature) {
      final value = _num(_telemetry['temperature']);
      if (value != null) items.add('${_format(value)}°C');
    }
    if (_showHumidity) {
      final value = _num(_telemetry['humidity']);
      if (value != null) items.add('Humidity ${_format(value)}%');
    }
    if (_showSoil) {
      final value = _num(_telemetry['soil']);
      if (value != null) items.add('Soil ${_format(value)}%');
    }
    if (_showWater) {
      final value = _num(_telemetry['waterLevel']);
      if (value != null) items.add('Water ${_format(value)}%');
    }
    if (_showMotors) {
      final m1 = _bool(_telemetry['led2'], false) ? 'ON' : 'OFF';
      final m2 = _bool(_telemetry['led3'], false) ? 'ON' : 'OFF';
      final m3 = _bool(_telemetry['led4'], false) ? 'ON' : 'OFF';
      items.add('M1 $m1  M2 $m2  M3 $m3');
    }

    String text;
    if (!_mqttConnected) {
      text = 'Connecting to your farm…';
    } else if (items.isEmpty) {
      text = 'Background monitoring is active';
    } else {
      text = items.join(' • ');
    }

    if (text.length > 190) {
      text = '${text.substring(0, 187)}…';
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: 'AGRO CONNECT • Live Monitor',
      notificationText: text,
      notificationIcon: const NotificationIcon(
        metaDataName: ForegroundMonitorService.iconMetaDataName,
        backgroundColor: Color(0xFF0F8F5F),
      ),
      notificationInitialRoute: '/',
    );
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return fallback;
  }

  static double? _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}
