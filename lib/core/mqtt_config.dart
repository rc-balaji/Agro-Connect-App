class MqttConfig {
  MqttConfig._();

  static const String broker = 'broker.emqx.io';
  static const int port = 1883;
  static const String deviceId = 'AGRO-001';

  static const String baseTopic = 'agroconnect/$deviceId';
  static const String telemetryTopic = '$baseTopic/telemetry';
  static const String desiredTopic = '$baseTopic/desired';
  static const String stateTopic = '$baseTopic/state';
  static const String statusTopic = '$baseTopic/status';

  static const Duration staleAfter = Duration(seconds: 5);
  static const Duration networkProbeInterval = Duration(seconds: 8);
  static const Duration commandTimeout = Duration(seconds: 5);
  static const int maxHistoryPoints = 300;
}
