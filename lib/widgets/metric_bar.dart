import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class MetricBar extends StatelessWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.trailing,
    required this.color,
    this.icon,
  });

  final String label;
  final double value;
  final double max;
  final String trailing;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final progress = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(trailing, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: progress,
                backgroundColor: AppTheme.border.withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
