import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../controllers/foreground_monitor_controller.dart';
import '../core/app_theme.dart';
import '../core/mqtt_config.dart';

class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgroController>();
    final background = context.watch<ForegroundMonitorController>();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        const Text(
          'Choose how AGRO CONNECT behaves in the background.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 16),
        _BackgroundStatusCard(
          background: background,
          controller: controller,
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Network',
          icon: Icons.network_check_rounded,
          children: [
            _Row(label: 'Transport', value: controller.network.label),
            _Row(
              label: 'Network interface',
              value: controller.network.hasInterface ? 'Available' : 'Unavailable',
            ),
            _Row(
              label: 'Internet reachability',
              value: controller.internetReachable ? 'Reachable' : 'Not reachable',
            ),
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
            _Row(
              label: 'Connection',
              value: controller.mqttConnected ? 'Connected' : 'Disconnected',
            ),
            _Row(
              label: 'Broker ping',
              value: controller.brokerPingLatencyMs > 0
                  ? '${controller.brokerPingLatencyMs} ms'
                  : '--',
            ),
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
            _Row(
              label: 'History points',
              value: '${controller.history.length} / ${MqttConfig.maxHistoryPoints}',
            ),
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
                  'This prototype uses a public MQTT broker. Use a private authenticated broker before a real farm deployment.',
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

class _BackgroundStatusCard extends StatelessWidget {
  const _BackgroundStatusCard({
    required this.background,
    required this.controller,
  });

  final ForegroundMonitorController background;
  final AgroController controller;

  @override
  Widget build(BuildContext context) {
    final preview = _previewText();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102B21), Color(0xFF0B1E17)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: AppTheme.emeraldSoft,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Background live status',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Keep selected farm readings visible even when the app is closed.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12.2, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: background.enabled,
                    onChanged: background.busy ? null : background.setEnabled,
                  ),
                ],
              ),
            ),
            if (!background.enabled && background.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        background.error!,
                        style: const TextStyle(color: AppTheme.red, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: !background.enabled
                  ? const SizedBox.shrink()
                  : Container(
                      key: const ValueKey('background-options'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        border: const Border(
                          top: BorderSide(color: AppTheme.border, width: 0.7),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: background.serviceRunning
                                      ? AppTheme.emerald
                                      : AppTheme.amber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                background.serviceRunning
                                    ? 'Background monitoring active'
                                    : 'Starting background monitoring…',
                                style: TextStyle(
                                  color: background.serviceRunning
                                      ? AppTheme.emeraldSoft
                                      : AppTheme.amber,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'SHOW IN LIVE NOTIFICATION',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _ToggleRow(
                            icon: Icons.sensors_rounded,
                            title: 'Device status',
                            subtitle: 'Online or offline',
                            value: background.showDevice,
                            onChanged: background.setShowDevice,
                          ),
                          _ToggleRow(
                            icon: Icons.thermostat_rounded,
                            title: 'Temperature',
                            value: background.showTemperature,
                            onChanged: background.setShowTemperature,
                          ),
                          _ToggleRow(
                            icon: Icons.water_drop_outlined,
                            title: 'Humidity',
                            value: background.showHumidity,
                            onChanged: background.setShowHumidity,
                          ),
                          _ToggleRow(
                            icon: Icons.grass_rounded,
                            title: 'Soil moisture',
                            value: background.showSoil,
                            onChanged: background.setShowSoil,
                          ),
                          _ToggleRow(
                            icon: Icons.water_rounded,
                            title: 'Water level',
                            value: background.showWater,
                            onChanged: background.setShowWater,
                          ),
                          _ToggleRow(
                            icon: Icons.power_rounded,
                            title: 'Motor status',
                            subtitle: 'Motor 1, 2 and 3',
                            value: background.showMotors,
                            onChanged: background.setShowMotors,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Divider(),
                          ),
                          _ToggleRow(
                            icon: Icons.event_available_rounded,
                            title: 'Plan activity alerts',
                            subtitle: 'A dismissible alert when a planned motor run starts or completes',
                            value: background.scheduleAlerts,
                            onChanged: background.setScheduleAlerts,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFF071710),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border.withValues(alpha: 0.8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'NOTIFICATION PREVIEW',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'AGRO CONNECT • Live Monitor',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  preview,
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (background.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              background.error!,
                              style: const TextStyle(
                                color: AppTheme.red,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _previewText() {
    final parts = <String>[];
    if (background.showDevice) {
      parts.add(controller.deviceOnline ? 'Online' : 'Offline');
    }
    if (background.showTemperature) {
      parts.add('${_format(controller.telemetry.temperature)}°C');
    }
    if (background.showHumidity) {
      parts.add('Humidity ${_format(controller.telemetry.humidity)}%');
    }
    if (background.showSoil) {
      parts.add('Soil ${_format(controller.telemetry.soil)}%');
    }
    if (background.showWater) {
      parts.add('Water ${_format(controller.telemetry.waterLevel)}%');
    }
    if (background.showMotors) {
      parts.add(
        'M1 ${controller.telemetry.led2 ? 'ON' : 'OFF'}  '
        'M2 ${controller.telemetry.led3 ? 'ON' : 'OFF'}  '
        'M3 ${controller.telemetry.led4 ? 'ON' : 'OFF'}',
      );
    }
    return parts.isEmpty ? 'Background monitoring is active' : parts.join(' • ');
  }

  String _format(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) return asDouble.round().toString();
    return asDouble.toStringAsFixed(1);
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: value
                  ? AppTheme.emerald.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? AppTheme.emeraldSoft : AppTheme.muted,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
          SelectableText(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppTheme.emeraldSoft,
            ),
          ),
        ],
      ),
    );
  }
}
