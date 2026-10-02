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
        Text('Monitor', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        const Text('Current field conditions', style: TextStyle(color: AppTheme.muted)),
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
          label: 'Tank Level',
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
            child: Row(
              children: [
                Icon(
                  controller.deviceOnline ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
                  color: controller.deviceOnline ? AppTheme.emerald : AppTheme.amber,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    controller.farmHealthText,
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
