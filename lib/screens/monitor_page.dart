import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import '../widgets/metric_bar.dart';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();
    final t = controller.telemetry;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Monitoring', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        const Text('Field conditions, sensor health and irrigation signals', style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 16),
        MetricBar(
          label: 'Soil Moisture',
          value: t.soil,
          max: 100,
          trailing: '${t.soil.toStringAsFixed(0)}%',
          color: t.soil < 30 ? AppTheme.red : AppTheme.emerald,
          icon: Icons.eco_rounded,
        ),
        const SizedBox(height: 12),
        MetricBar(
          label: 'Tank Water Level',
          value: t.waterLevel,
          max: 100,
          trailing: '${t.waterLevel.toStringAsFixed(0)}%',
          color: t.waterLevel < 15 ? AppTheme.red : AppTheme.cyan,
          icon: Icons.waves_rounded,
        ),
        const SizedBox(height: 12),
        MetricBar(
          label: 'Humidity',
          value: t.humidity,
          max: 100,
          trailing: '${t.humidity.toStringAsFixed(0)}%',
          color: AppTheme.cyan,
          icon: Icons.water_drop_outlined,
        ),
        const SizedBox(height: 12),
        MetricBar(
          label: 'Temperature',
          value: t.temperature,
          max: 50,
          trailing: '${t.temperature.toStringAsFixed(1)}°C',
          color: t.temperature > 38 ? AppTheme.red : AppTheme.amber,
          icon: Icons.thermostat_rounded,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sensor Diagnostics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 14),
                _Diagnostic(label: 'Telemetry sequence', value: '${t.sequence}', good: controller.deviceOnline),
                _Diagnostic(label: 'Soil raw ADC', value: '${t.soilRaw}', good: t.soilRaw > 0),
                _Diagnostic(label: 'Water distance', value: '${t.waterDistance.toStringAsFixed(1)} cm', good: t.waterDistance > 0),
                _Diagnostic(label: 'ESP32 uptime', value: _duration(t.uptimeMs), good: t.uptimeMs > 0),
                _Diagnostic(label: 'MQTT ping/pong', value: controller.brokerPingLatencyMs > 0 ? '${controller.brokerPingLatencyMs} ms' : '--', good: controller.mqttConnected),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _duration(int ms) {
    final seconds = ms ~/ 1000;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }
}

class _Diagnostic extends StatelessWidget {
  const _Diagnostic({required this.label, required this.value, required this.good});

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(good ? Icons.check_circle_rounded : Icons.remove_circle_outline, size: 17, color: good ? AppTheme.emerald : AppTheme.muted),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
