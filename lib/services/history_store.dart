import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/mqtt_config.dart';
import '../models/telemetry.dart';

class HistoryStore {
  static const String _key = 'agro_connect_history_v1';

  Future<List<Telemetry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Telemetry>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Telemetry>[];

      return decoded
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            final timestamp = (map['receivedAt'] as num?)?.toInt() ?? 0;
            return Telemetry.fromMap(
              map,
              receivedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
            );
          })
          .toList(growable: true);
    } catch (_) {
      return <Telemetry>[];
    }
  }

  Future<void> save(List<Telemetry> history) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = history.length > MqttConfig.maxHistoryPoints
        ? history.sublist(history.length - MqttConfig.maxHistoryPoints)
        : history;
    final encoded = jsonEncode(trimmed.map((item) => item.toMap()).toList());
    await prefs.setString(_key, encoded);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
