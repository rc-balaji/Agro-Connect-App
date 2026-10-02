import 'package:flutter/foundation.dart';

import '../models/schedule_plan.dart';
import '../services/schedule_service.dart';

class PlanController extends ChangeNotifier {
  PlanController({ScheduleService? service}) : _service = service ?? ScheduleService();

  final ScheduleService _service;

  final List<SchedulePlan> _plans = <SchedulePlan>[];
  List<SchedulePlan> get plans => List<SchedulePlan>.unmodifiable(_plans);

  bool _initialized = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  SchedulerHealth _health = const SchedulerHealth(ok: false, configured: false);

  bool get initialized => _initialized;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  SchedulerHealth get health => _health;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        _service.fetchSchedules(),
        _service.fetchSchedulerHealth(),
      ]);
      _plans
        ..clear()
        ..addAll(results[0] as List<SchedulePlan>);
      _sort();
      _health = results[1] as SchedulerHealth;
    } catch (error) {
      _error = _message(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> create(ScheduleDraft draft) async {
    return _runSave(() async {
      final created = await _service.createSchedule(draft);
      _plans.add(created);
      _sort();
    });
  }

  Future<bool> update(String id, ScheduleDraft draft) async {
    return _runSave(() async {
      final updated = await _service.updateSchedule(id, draft.toMap());
      final index = _plans.indexWhere((plan) => plan.id == id);
      if (index >= 0) {
        _plans[index] = updated;
      } else {
        _plans.add(updated);
      }
      _sort();
    });
  }

  Future<bool> setEnabled(SchedulePlan plan, bool enabled) async {
    return _runSave(() async {
      final updated = await _service.updateSchedule(plan.id, <String, dynamic>{
        'enabled': enabled,
      });
      final index = _plans.indexWhere((item) => item.id == plan.id);
      if (index >= 0) _plans[index] = updated;
      _sort();
    });
  }

  Future<bool> duplicate(SchedulePlan plan) async {
    final draft = ScheduleDraft(
      title: '${plan.title} copy',
      motor: plan.motor,
      date: plan.date,
      time: plan.time,
      durationSec: plan.durationSec,
      repeat: plan.repeat,
      weekdays: plan.weekdays,
      endDate: plan.endDate,
      enabled: false,
    );
    return create(draft);
  }

  Future<bool> delete(String id) async {
    return _runSave(() async {
      await _service.deleteSchedule(id);
      _plans.removeWhere((plan) => plan.id == id);
    });
  }

  List<SchedulePlan> plansForMotor(int motor) {
    return _plans.where((plan) => plan.motor == motor).toList(growable: false);
  }

  List<SchedulePlan> plansForDay(int motor, DateTime day) {
    return _plans
        .where((plan) => plan.motor == motor && plan.occursOn(day))
        .toList(growable: false)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<SchedulePlan> upcomingForMotor(int motor) {
    final list = _plans.where((plan) => plan.motor == motor).toList();
    list.sort((a, b) {
      final aNext = a.nextRunAt ?? 0x7fffffffffffffff;
      final bNext = b.nextRunAt ?? 0x7fffffffffffffff;
      return aNext.compareTo(bNext);
    });
    return list;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> _runSave(Future<void> Function() operation) async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await operation();
      _health = await _service.fetchSchedulerHealth();
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  String _message(Object error) {
    if (error is ScheduleApiException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _sort() {
    _plans.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.time.compareTo(b.time);
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
