class SchedulePlan {
  const SchedulePlan({
    required this.id,
    required this.title,
    required this.motor,
    required this.date,
    required this.time,
    required this.durationSec,
    required this.repeat,
    required this.weekdays,
    required this.enabled,
    required this.timezone,
    this.endDate,
    this.nextRunAt,
    this.createdAt,
    this.updatedAt,
    this.lastTriggeredAt,
    this.lastResult,
    this.lastPhase,
    this.schedulerStatus,
    this.schedulerNextAlarmAt,
    this.expired = false,
  });

  final String id;
  final String title;
  final int motor;
  final String date;
  final String time;
  final int durationSec;
  final String repeat;
  final List<int> weekdays;
  final String? endDate;
  final bool enabled;
  final String timezone;
  final int? nextRunAt;
  final int? createdAt;
  final int? updatedAt;
  final int? lastTriggeredAt;
  final String? lastResult;
  final String? lastPhase;
  final String? schedulerStatus;
  final int? schedulerNextAlarmAt;
  final bool expired;

  factory SchedulePlan.fromMap(Map<String, dynamic> map) {
    int? asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    return SchedulePlan(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Motor plan',
      motor: asInt(map['motor']) ?? 1,
      date: map['date']?.toString() ?? '',
      time: normalizeTime(map['time']?.toString() ?? '00:00:00'),
      durationSec: asInt(map['durationSec']) ?? 1,
      repeat: map['repeat']?.toString() ?? 'once',
      weekdays: (map['weekdays'] is List)
          ? (map['weekdays'] as List)
              .map((value) => asInt(value))
              .whereType<int>()
              .toList(growable: false)
          : const <int>[],
      endDate: map['endDate']?.toString().isNotEmpty == true
          ? map['endDate'].toString()
          : null,
      enabled: map['enabled'] != false,
      timezone: map['timezone']?.toString() ?? 'Asia/Kolkata',
      nextRunAt: asInt(map['nextRunAt']),
      createdAt: asInt(map['createdAt']),
      updatedAt: asInt(map['updatedAt']),
      lastTriggeredAt: asInt(map['lastTriggeredAt']),
      lastResult: map['lastResult']?.toString(),
      lastPhase: map['lastPhase']?.toString(),
      schedulerStatus: map['schedulerStatus']?.toString(),
      schedulerNextAlarmAt: asInt(map['schedulerNextAlarmAt']),
      expired: map['expired'] == true,
    );
  }

  static String normalizeTime(String value) {
    final parts = value.split(':');
    if (parts.length == 2) return '$value:00';
    return value;
  }

  Map<String, dynamic> toRequestMap() {
    return <String, dynamic>{
      'title': title,
      'motor': motor,
      'date': date,
      'time': time,
      'durationSec': durationSec,
      'repeat': repeat,
      'weekdays': weekdays,
      'endDate': endDate,
      'enabled': enabled,
      'timezone': timezone,
    };
  }

  SchedulePlan copyWith({
    String? id,
    String? title,
    int? motor,
    String? date,
    String? time,
    int? durationSec,
    String? repeat,
    List<int>? weekdays,
    String? endDate,
    bool clearEndDate = false,
    bool? enabled,
    String? timezone,
    int? nextRunAt,
    int? createdAt,
    int? updatedAt,
    int? lastTriggeredAt,
    String? lastResult,
    String? lastPhase,
    String? schedulerStatus,
    int? schedulerNextAlarmAt,
    bool? expired,
  }) {
    return SchedulePlan(
      id: id ?? this.id,
      title: title ?? this.title,
      motor: motor ?? this.motor,
      date: date ?? this.date,
      time: time ?? this.time,
      durationSec: durationSec ?? this.durationSec,
      repeat: repeat ?? this.repeat,
      weekdays: weekdays ?? this.weekdays,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      enabled: enabled ?? this.enabled,
      timezone: timezone ?? this.timezone,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      lastResult: lastResult ?? this.lastResult,
      lastPhase: lastPhase ?? this.lastPhase,
      schedulerStatus: schedulerStatus ?? this.schedulerStatus,
      schedulerNextAlarmAt: schedulerNextAlarmAt ?? this.schedulerNextAlarmAt,
      expired: expired ?? this.expired,
    );
  }

  bool occursOn(DateTime day) {
    final key = dateKey(day);
    if (key.compareTo(date) < 0) return false;
    if (endDate != null && key.compareTo(endDate!) > 0) return false;

    switch (repeat) {
      case 'once':
        return key == date;
      case 'daily':
        return true;
      case 'weekly':
        return weekdays.contains(apiWeekday(day));
      default:
        return false;
    }
  }

  String get repeatLabel {
    switch (repeat) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return weekdaysLabel;
      default:
        return 'Once';
    }
  }

  String get weekdaysLabel {
    if (weekdays.isEmpty) return 'Selected days';
    const labels = <int, String>{
      0: 'Sun',
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
    };
    return weekdays.map((day) => labels[day] ?? '').where((e) => e.isNotEmpty).join(', ');
  }

  String get durationLabel {
    if (durationSec < 60) return '$durationSec sec';
    if (durationSec % 3600 == 0) {
      final hours = durationSec ~/ 3600;
      return '$hours ${hours == 1 ? 'hr' : 'hrs'}';
    }
    if (durationSec % 60 == 0) {
      final minutes = durationSec ~/ 60;
      return '$minutes min';
    }
    final minutes = durationSec ~/ 60;
    final seconds = durationSec % 60;
    return '$minutes min $seconds sec';
  }

  String get displayTime => to12Hour(time);

  static int apiWeekday(DateTime day) => day.weekday % 7;

  static String dateKey(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static DateTime parseDateKey(String value) {
    final parts = value.split('-').map(int.parse).toList(growable: false);
    return DateTime(parts[0], parts[1], parts[2]);
  }

  static String to12Hour(String value) {
    final p = normalizeTime(value).split(':');
    final hour24 = int.tryParse(p[0]) ?? 0;
    final minute = int.tryParse(p[1]) ?? 0;
    final second = int.tryParse(p[2]) ?? 0;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final sec = second == 0 ? '' : ':${second.toString().padLeft(2, '0')}';
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}$sec $suffix';
  }

  static DateTime istDateTimeFromEpoch(int epochMs) {
    return DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        .add(const Duration(hours: 5, minutes: 30));
  }
}

class ScheduleDraft {
  const ScheduleDraft({
    required this.title,
    required this.motor,
    required this.date,
    required this.time,
    required this.durationSec,
    required this.repeat,
    required this.weekdays,
    required this.enabled,
    this.endDate,
  });

  final String title;
  final int motor;
  final String date;
  final String time;
  final int durationSec;
  final String repeat;
  final List<int> weekdays;
  final String? endDate;
  final bool enabled;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'title': title,
        'motor': motor,
        'date': date,
        'time': time,
        'durationSec': durationSec,
        'repeat': repeat,
        'weekdays': weekdays,
        'endDate': endDate,
        'enabled': enabled,
        'timezone': 'Asia/Kolkata',
      };
}
