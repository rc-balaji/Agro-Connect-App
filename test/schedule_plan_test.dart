import 'package:flutter_test/flutter_test.dart';
import 'package:agro_connect/models/schedule_plan.dart';

void main() {
  test('weekly plan occurs only on selected API weekdays', () {
    final plan = SchedulePlan(
      id: 'p1',
      title: 'Weekday plan',
      motor: 1,
      date: '2026-10-01',
      time: '07:30:15',
      durationSec: 45,
      repeat: 'weekly',
      weekdays: const [1, 3, 5],
      enabled: true,
      timezone: 'Asia/Kolkata',
    );

    expect(plan.occursOn(DateTime(2026, 10, 2)), isTrue); // Friday
    expect(plan.occursOn(DateTime(2026, 10, 3)), isFalse); // Saturday
    expect(plan.occursOn(DateTime(2026, 10, 5)), isTrue); // Monday
  });

  test('duration label keeps seconds', () {
    final plan = SchedulePlan(
      id: 'p2',
      title: 'Seconds plan',
      motor: 2,
      date: '2026-10-02',
      time: '19:30:15',
      durationSec: 75,
      repeat: 'once',
      weekdays: const [],
      enabled: true,
      timezone: 'Asia/Kolkata',
    );

    expect(plan.durationLabel, '1 min 15 sec');
    expect(plan.displayTime, '07:30:15 PM');
  });
}
