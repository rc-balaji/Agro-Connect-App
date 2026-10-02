import 'dart:convert';

class CygnusMessage {
  const CygnusMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.kind = 'text',
    this.payload = const <String, dynamic>{},
  });

  final String id;
  final String role; // user | assistant | system
  final String text;
  final DateTime createdAt;
  final String kind;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'role': role,
        'text': text,
        'kind': kind,
        'payload': payload,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory CygnusMessage.fromMap(Map<String, dynamic> map) {
    final ts = map['createdAt'];
    final epoch = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    return CygnusMessage(
      id: map['id']?.toString() ?? '',
      role: map['role']?.toString() ?? 'assistant',
      text: map['text']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'text',
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const <String, dynamic>{},
      createdAt: epoch > 0
          ? DateTime.fromMillisecondsSinceEpoch(epoch)
          : DateTime.now(),
    );
  }

  String encode() => jsonEncode(toMap());

  factory CygnusMessage.decode(String value) =>
      CygnusMessage.fromMap(Map<String, dynamic>.from(jsonDecode(value) as Map));
}

class CygnusSessionSummary {
  const CygnusSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.languageCode = 'en',
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String languageCode;

  factory CygnusSessionSummary.fromMap(String id, Map<String, dynamic> map) {
    final ts = map['updatedAt'];
    final epoch = ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0;
    return CygnusSessionSummary(
      id: id,
      title: map['title']?.toString() ?? 'New chat',
      languageCode: map['languageCode']?.toString() ?? 'en',
      updatedAt: epoch > 0
          ? DateTime.fromMillisecondsSinceEpoch(epoch)
          : DateTime.now(),
    );
  }
}

class PendingCygnusAction {
  const PendingCygnusAction({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.arguments,
  });

  final String id;
  final String type;
  final String title;
  final String details;
  final Map<String, dynamic> arguments;
}
