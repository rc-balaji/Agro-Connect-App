import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/foreground_monitor_service.dart';

class ForegroundMonitorController extends ChangeNotifier {
  bool _initialized = false;
  bool _busy = false;
  bool _enabled = false;
  bool _serviceRunning = false;
  bool _showDevice = true;
  bool _showTemperature = true;
  bool _showHumidity = true;
  bool _showSoil = true;
  bool _showWater = true;
  bool _showMotors = false;
  bool _scheduleAlerts = true;
  String? _error;

  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get enabled => _enabled;
  bool get serviceRunning => _serviceRunning;
  bool get showDevice => _showDevice;
  bool get showTemperature => _showTemperature;
  bool get showHumidity => _showHumidity;
  bool get showSoil => _showSoil;
  bool get showWater => _showWater;
  bool get showMotors => _showMotors;
  bool get scheduleAlerts => _scheduleAlerts;
  String? get error => _error;

  Future<void> initialize() async {
    if (_initialized) return;
    ForegroundMonitorService.initializePlugin();
    final values = await ForegroundMonitorService.readPreferences();
    _enabled = values[ForegroundPreferenceKeys.enabled] ?? false;
    _showDevice = values[ForegroundPreferenceKeys.showDevice] ?? true;
    _showTemperature = values[ForegroundPreferenceKeys.showTemperature] ?? true;
    _showHumidity = values[ForegroundPreferenceKeys.showHumidity] ?? true;
    _showSoil = values[ForegroundPreferenceKeys.showSoil] ?? true;
    _showWater = values[ForegroundPreferenceKeys.showWater] ?? true;
    _showMotors = values[ForegroundPreferenceKeys.showMotors] ?? false;
    _scheduleAlerts = values[ForegroundPreferenceKeys.scheduleAlerts] ?? true;
    _serviceRunning = await FlutterForegroundTask.isRunningService;
    _initialized = true;
    notifyListeners();

    if (_enabled && Platform.isAndroid && !_serviceRunning) {
      await _startSilently();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_busy || value == _enabled) return;
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      if (value) {
        if (!Platform.isAndroid) {
          _error = 'Background live status is currently available on Android.';
          return;
        }
        final permissionGranted = await ForegroundMonitorService.requestNotificationPermission();
        if (!permissionGranted) {
          _error = 'Notification permission is required for background live status.';
          return;
        }

        _enabled = true;
        await _persist();
        _serviceRunning = await ForegroundMonitorService.start();
        if (!_serviceRunning) {
          _enabled = false;
          await _persist();
          _error = 'Could not start background monitoring. Try again.';
        }
      } else {
        _enabled = false;
        await _persist();
        await ForegroundMonitorService.stop();
        _serviceRunning = false;
      }
    } catch (error) {
      debugPrint('Foreground monitor toggle failed: $error');
      _error = 'Could not update background monitoring. Try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> setShowDevice(bool value) => _setPreference(() => _showDevice = value);
  Future<void> setShowTemperature(bool value) => _setPreference(() => _showTemperature = value);
  Future<void> setShowHumidity(bool value) => _setPreference(() => _showHumidity = value);
  Future<void> setShowSoil(bool value) => _setPreference(() => _showSoil = value);
  Future<void> setShowWater(bool value) => _setPreference(() => _showWater = value);
  Future<void> setShowMotors(bool value) => _setPreference(() => _showMotors = value);
  Future<void> setScheduleAlerts(bool value) => _setPreference(() => _scheduleAlerts = value);

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> refreshServiceState() async {
    _serviceRunning = await FlutterForegroundTask.isRunningService;
    notifyListeners();
  }

  Future<void> _startSilently() async {
    try {
      _serviceRunning = await ForegroundMonitorService.start();
    } catch (error) {
      debugPrint('Foreground monitor auto-start failed: $error');
      _serviceRunning = false;
    }
    notifyListeners();
  }

  Future<void> _setPreference(VoidCallback update) async {
    if (!_enabled) return;
    update();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() {
    return ForegroundMonitorService.savePreferences(<String, bool>{
      ForegroundPreferenceKeys.enabled: _enabled,
      ForegroundPreferenceKeys.showDevice: _showDevice,
      ForegroundPreferenceKeys.showTemperature: _showTemperature,
      ForegroundPreferenceKeys.showHumidity: _showHumidity,
      ForegroundPreferenceKeys.showSoil: _showSoil,
      ForegroundPreferenceKeys.showWater: _showWater,
      ForegroundPreferenceKeys.showMotors: _showMotors,
      ForegroundPreferenceKeys.scheduleAlerts: _scheduleAlerts,
    });
  }
}
