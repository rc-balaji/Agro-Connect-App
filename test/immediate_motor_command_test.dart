import 'package:flutter_test/flutter_test.dart';
import 'package:agro_connect/cygnus/immediate_motor_command.dart';

void main() {
  test('clear commands from device testing use the direct path', () {
    for (final text in [
      'motor 2 on pannu',
      'Motor 2 va On Pannu',
      'second motor start',
    ]) {
      final command = ImmediateMotorCommand.parse(text)!;
      expect(command.motor, 2);
      expect(command.enabled, true);
    }
    expect(
      ImmediateMotorCommand.parse('Motor 2 ah Stop pannu')!.enabled,
      false,
    );
    final all = ImmediateMotorCommand.parse('Switch off all the motors');
    // Extra grammar must be explicitly supported, never guessed from keywords.
    expect(all!.motor, isNull);
    expect(all.enabled, false);
    expect(ImmediateMotorCommand.parse('stop all motors')!.motor, isNull);
  });
  test(
    'questions, negations, schedules and conflicting targets never actuate locally',
    () {
      for (final text in [
        "don't start motor 1",
        'is motor 1 on?',
        'motor 1 on tomorrow',
        'motor 1 on at 5',
        'motor 1 on and motor 2 off',
        'motor 4 on',
        'please do not start motor 2',
        'if soil is dry motor 1 on',
        'motor 1 on for 5 minutes',
      ]) {
        expect(ImmediateMotorCommand.parse(text), isNull, reason: text);
      }
    },
  );
}
