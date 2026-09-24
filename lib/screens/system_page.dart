import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import '../core/mqtt_config.dart';

class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('System', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        const Text('Network, MQTT transport and app diagnostics', style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 16),
        _Section(
          title: 'Network',
          icon: Icons.network_check_rounded,
          children: [
            _Row(label: 'Transport', value: controller.network.label),
            _Row(label: 'Network interface', value: controller.network.hasInterface ? 'Available' : 'Unavailable'),
            _Row(label: 'Internet reachability', value: controller.internetReachable ? 'Reachable' : 'Not reachable'),
            _Row(
              label: 'Last network check',
              value: controller.network.lastChecked == null
                  ? '--'
                  : TimeOfDay.fromDateTime(controller.network.lastChecked!).format(context),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.refreshNetwork,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Run Network Check'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'MQTT',
          icon: Icons.hub_rounded,
          children: [
            const _Row(label: 'Broker', value: MqttConfig.broker),
            const _Row(label: 'Port', value: '${MqttConfig.port}'),
            _Row(label: 'Connection', value: controller.mqttConnected ? 'Connected' : 'Disconnected'),
            _Row(label: 'Broker ping', value: controller.brokerPingLatencyMs > 0 ? '${controller.brokerPingLatencyMs} ms' : '--'),
            const _Row(label: 'Device', value: MqttConfig.deviceId),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.internetReachable ? controller.reconnectMqtt : null,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Reconnect MQTT'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Section(
          title: 'Topics',
          icon: Icons.route_rounded,
          children: [
            _Topic(label: 'Telemetry', value: MqttConfig.telemetryTopic),
            _Topic(label: 'Desired', value: MqttConfig.desiredTopic),
            _Topic(label: 'State / ACK', value: MqttConfig.stateTopic),
            _Topic(label: 'Status', value: MqttConfig.statusTopic),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Local Data',
          icon: Icons.storage_rounded,
          children: [
            _Row(label: 'History points', value: '${controller.history.length} / ${MqttConfig.maxHistoryPoints}'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.history.isEmpty ? null : controller.clearHistory,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Clear Local History'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.amber.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppTheme.amber, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This build uses broker.emqx.io, a public MQTT broker, for prototype/demo traffic. Use a private authenticated broker before a real deployment.',
                  style: TextStyle(color: AppTheme.muted, height: 1.45, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.emerald, size: 20),
                const SizedBox(width: 9),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted))),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _Topic extends StatelessWidget {
  const _Topic({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.emeraldSoft)),
        ],
      ),
    );
  }
}
