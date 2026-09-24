import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.subtitle,
    this.points = const <double>[],
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final List<double> points;

  @override
  Widget build(BuildContext context) {
    final data = points.length > 36 ? points.sublist(points.length - 36) : points;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(subtitle!, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: data.length < 2
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Waiting for live data…', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (data.length - 1).toDouble(),
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i]),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            barWidth: 2.2,
                            color: color,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  color.withValues(alpha: 0.18),
                                  color.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 180),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
