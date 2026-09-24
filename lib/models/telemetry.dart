import 'dart:convert';

class Telemetry {
  const Telemetry({
    required this.receivedAt,
    this.temperature = 0,
    this.humidity = 0,
    this.soil = 0,
    this.waterLevel = 0,
    this.led1 = false,
    this.led2 = false,
    this.led3 = false,
    this.led4 = false,
    this.sequence = 0,
    this.uptimeMs = 0,
    this.soilRaw = 0,
    this.waterDistance = 0,
  });

  final DateTime receivedAt;
  final double temperature;
  final double humidity;
  final double soil;
  final double waterLevel;
  final bool led1;
  final bool led2;
  final bool led3;
  final bool led4;
  final int sequence;
  final int uptimeMs;
  final int soilRaw;
  final double waterDistance;

  factory Telemetry.empty() => Telemetry(receivedAt: DateTime.fromMillisecondsSinceEpoch(0));

  factory Telemetry.fromMap(Map<String, dynamic> map, {DateTime? receivedAt}) {
    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int integer(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool boolean(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value?.toString().toLowerCase() == 'true';
    }

    return Telemetry(
      receivedAt: receivedAt ?? DateTime.now(),
      temperature: number(map['temperature']),
      humidity: number(map['humidity']),
      soil: number(map['soil']),
      waterLevel: number(map['waterLevel']),
      led1: boolean(map['led1']),
      led2: boolean(map['led2']),
      led3: boolean(map['led3']),
      led4: boolean(map['led4']),
      sequence: integer(map['seq']),
      uptimeMs: integer(map['uptimeMs']),
      soilRaw: integer(map['soilRaw']),
      waterDistance: number(map['waterDistance']),
    );
  }

  Map<String, dynamic> toMap() => {
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'temperature': temperature,
        'humidity': humidity,
        'soil': soil,
        'waterLevel': waterLevel,
        'led1': led1,
        'led2': led2,
        'led3': led3,
        'led4': led4,
        'seq': sequence,
        'uptimeMs': uptimeMs,
        'soilRaw': soilRaw,
        'waterDistance': waterDistance,
      };

  String toJson() => jsonEncode(toMap());

  factory Telemetry.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return Telemetry.fromMap(
      map,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['receivedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
