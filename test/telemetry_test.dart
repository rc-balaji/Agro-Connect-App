import 'package:agro_connect/models/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses telemetry payload', () {
    final telemetry = Telemetry.fromMap({
      'temperature': 28.5,
      'humidity': 65,
      'soil': 42,
      'waterLevel': 78,
      'led1': true,
      'led2': false,
      'seq': 7,
    });

    expect(telemetry.temperature, 28.5);
    expect(telemetry.humidity, 65);
    expect(telemetry.soil, 42);
    expect(telemetry.waterLevel, 78);
    expect(telemetry.led1, isTrue);
    expect(telemetry.sequence, 7);
  });
}
