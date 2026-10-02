import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_pill.dart';

class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();
    final t = controller.telemetry;
    final history = controller.history;

    final temperature = history.map((e) => e.temperature).toList(growable: false);
    final humidity = history.map((e) => e.humidity).toList(growable: false);
    final soil = history.map((e) => e.soil).toList(growable: false);
    final water = history.map((e) => e.waterLevel).toList(growable: false);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          sliver: SliverList.list(
            children: [
              _Hero(controller: controller),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 650;
                  final width = twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: width,
                        child: SensorCard(
                          title: 'Temperature',
                          value: t.temperature.toStringAsFixed(1),
                          unit: '°C',
                          icon: Icons.thermostat_rounded,
                          color: const Color(0xFFFF8C92),
                          subtitle: 'Air temperature',
                          points: temperature,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SensorCard(
                          title: 'Humidity',
                          value: t.humidity.toStringAsFixed(0),
                          unit: '%',
                          icon: Icons.water_drop_outlined,
                          color: AppTheme.cyan,
                          subtitle: 'Air humidity',
                          points: humidity,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SensorCard(
                          title: 'Soil Moisture',
                          value: t.soil.toStringAsFixed(0),
                          unit: '%',
                          icon: Icons.eco_rounded,
                          color: AppTheme.emerald,
                          subtitle: 'Current soil level',
                          points: soil,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SensorCard(
                          title: 'Water Level',
                          value: t.waterLevel.toStringAsFixed(0),
                          unit: '%',
                          icon: Icons.waves_rounded,
                          color: const Color(0xFF5EB6FF),
                          subtitle: 'Current tank level',
                          points: water,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.emerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.agriculture_rounded, color: AppTheme.emerald),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Farm Health', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(controller.farmHealthText, style: const TextStyle(color: AppTheme.muted, height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.controller});

  final AgroController controller;

  @override
  Widget build(BuildContext context) {
    final age = controller.packetAge;
    final ageText = age == null
        ? 'Waiting'
        : age.inSeconds < 1
            ? 'Live now'
            : '${age.inSeconds}s ago';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2D21), Color(0xFF091A14)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.emerald,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.eco_rounded, color: Color(0xFF063426)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Farm Overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    SizedBox(height: 3),
                    Text('Live field conditions', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.2)),
                ),
                child: const Text('LIVE', style: TextStyle(color: AppTheme.emeraldSoft, fontWeight: FontWeight.w800, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(label: 'Farm device', active: controller.deviceOnline),
              StatusPill(
                label: 'Internet',
                active: controller.internetReachable,
                icon: controller.internetReachable ? Icons.public_rounded : Icons.public_off_rounded,
                activeText: controller.network.label,
                inactiveText: controller.network.label,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniInfo(label: 'Last update', value: ageText),
              const SizedBox(width: 10),
              _MiniInfo(
                label: 'Connection',
                value: controller.deviceOnline ? 'Active' : 'Waiting',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
            const SizedBox(height: 4),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
