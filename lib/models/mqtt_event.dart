class MqttEvent {
  const MqttEvent({required this.topic, required this.payload});

  final String topic;
  final Map<String, dynamic> payload;
}
