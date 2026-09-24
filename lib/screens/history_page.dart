import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import '../models/telemetry.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _metric = 'soil';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();
    final history = controller.history;
    final visible = history.length > 80 ? history.sublist(history.length - 80) : history;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('${history.length} locally cached readings', style: const TextStyle(color: AppTheme.muted)),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Clear history',
              onPressed: history.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear history?'),
                          content: const Text('This removes locally cached telemetry from this phone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await context.read<AgroController>().clearHistory();
                      }
                    },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'soil', label: Text('Soil'), icon: Icon(Icons.eco_rounded)),
              ButtonSegment(value: 'water', label: Text('Water'), icon: Icon(Icons.waves_rounded)),
              ButtonSegment(value: 'temperature', label: Text('Temp'), icon: Icon(Icons.thermostat_rounded)),
              ButtonSegment(value: 'humidity', label: Text('Humidity'), icon: Icon(Icons.water_drop_outlined)),
            ],
            selected: {_metric},
            onSelectionChanged: (selection) => setState(() => _metric = selection.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 18, 12),
            child: SizedBox(
              height: 260,
              child: visible.length < 2
                  ? const Center(child: Text('Waiting for enough telemetry to draw history…', style: TextStyle(color: AppTheme.muted)))
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (visible.length - 1).toDouble(),
                        minY: _minY(visible),
                        maxY: _maxY(visible),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: _interval(visible),
                          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border.withValues(alpha: 0.5), strokeWidth: 0.7),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              getTitlesWidget: (value, meta) => Text(
                                value.toStringAsFixed(0),
                                style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) => spots
                                .map(
                                  (spot) => LineTooltipItem(
                                    _tooltipLabel(visible[spot.x.toInt()]),
                                    const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w700),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < visible.length; i++) FlSpot(i.toDouble(), _value(visible[i])),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            barWidth: 2.4,
                            color: _color,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_color.withValues(alpha: 0.2), _color.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 200),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Readings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('No history yet.', style: TextStyle(color: AppTheme.muted)),
                  )
                else
                  for (final item in history.reversed.take(12)) _HistoryRow(item: item),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color get _color {
    switch (_metric) {
      case 'temperature':
        return const Color(0xFFFF8C92);
      case 'humidity':
        return AppTheme.cyan;
      case 'water':
        return const Color(0xFF5EB6FF);
      default:
        return AppTheme.emerald;
    }
  }

  double _value(Telemetry item) {
    switch (_metric) {
      case 'temperature':
        return item.temperature;
      case 'humidity':
        return item.humidity;
      case 'water':
        return item.waterLevel;
      default:
        return item.soil;
    }
  }

  double _minY(List<Telemetry> data) {
    final values = data.map(_value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    return (min - 5).clamp(0, double.infinity).toDouble();
  }

  double _maxY(List<Telemetry> data) {
    final values = data.map(_value).toList();
    final max = values.reduce((a, b) => a > b ? a : b);
    final upper = _metric == 'temperature' ? 50.0 : 100.0;
    return (max + 5).clamp(10, upper).toDouble();
  }

  double _interval(List<Telemetry> data) {
    final range = _maxY(data) - _minY(data);
    return range <= 20 ? 5 : range <= 50 ? 10 : 20;
  }

  String _tooltipLabel(Telemetry item) {
    final time = TimeOfDay.fromDateTime(item.receivedAt).format(context);
    final suffix = _metric == 'temperature' ? '°C' : '%';
    return '$time\n${_value(item).toStringAsFixed(1)}$suffix';
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final Telemetry item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(TimeOfDay.fromDateTime(item.receivedAt).format(context), style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          ),
          Expanded(child: Text('${item.temperature.toStringAsFixed(1)}°C', style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('H ${item.humidity.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.muted))),
          Expanded(child: Text('S ${item.soil.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.muted))),
          Expanded(child: Text('W ${item.waterLevel.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.muted))),
        ],
      ),
    );
  }
}
