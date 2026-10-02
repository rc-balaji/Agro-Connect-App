import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import '../widgets/motor_card.dart';

class ControlPage extends StatelessWidget {
  const ControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();
    final c = controller.controls;
    final enabled = controller.deviceOnline && controller.mqttConnected;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const _PageHeader(
          icon: Icons.tune_rounded,
          title: 'Motors',
          subtitle: 'Manual motor control',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.emerald),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Automatic Irrigation', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('Based on soil moisture', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                    ],
                  ),
                ),
                Text(
                  c.actual1 ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: c.actual1 ? AppTheme.emerald : AppTheme.muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        MotorCard(
          number: 1,
          desiredOn: c.desired2,
          actualOn: c.actual2,
          enabled: enabled,
          pending: c.pendingKey == 'motor1',
          onChanged: (value) => controller.setMotor(1, value),
        ),
        const SizedBox(height: 12),
        MotorCard(
          number: 2,
          desiredOn: c.desired3,
          actualOn: c.actual3,
          enabled: enabled,
          pending: c.pendingKey == 'motor2',
          onChanged: (value) => controller.setMotor(2, value),
        ),
        const SizedBox(height: 12),
        MotorCard(
          number: 3,
          desiredOn: c.desired4,
          actualOn: c.actual4,
          enabled: enabled,
          pending: c.pendingKey == 'motor3',
          onChanged: (value) => controller.setMotor(3, value),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  enabled ? Icons.bolt_rounded : Icons.lock_clock_rounded,
                  color: enabled ? AppTheme.emerald : AppTheme.amber,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    enabled
                        ? 'Ready to control'
                        : 'Controls unavailable. Check the connection.',
                    style: const TextStyle(color: AppTheme.muted, height: 1.4),
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

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.emerald.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: AppTheme.emerald),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
