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

  factory CygnusMessage.decode(String value) => CygnusMessage.fromMap(
    Map<String, dynamic>.from(jsonDecode(value) as Map),
  );
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

enum CygnusDecision { none, approve, skip }

CygnusDecision parseCygnusDecision(String input) {
  final normalized = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'[.!?,]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  if (const {
    'yes',
    'yes retry',
    'yes retry once',
    'retry',
    'retry once',
    'try again',
    'yes confirm',
    'yes proceed',
    'confirm',
    'do it',
    'proceed',
    'go ahead',
    'okay',
    'ok',
    'pannidu',
    'pannu',
    'ama',
    'aama',
    'seri',
    'சரி',
    'ஆம்',
    'பண்ணிடு',
  }.contains(normalized)) {
    return CygnusDecision.approve;
  }

  if (const {
    'no',
    'no cancel',
    'cancel',
    'stop',
    'skip',
    'skip it',
    'skip this',
    'leave it',
    'leave that',
    'leave this',
    'no leave it',
    'no leave that',
    'no need',
    'dont retry',
    'do not retry',
    'venam',
    'vendam',
    'illa',
    'illai',
    'vidu',
    'vittudu',
    'paravalla',
    'வேண்டாம்',
    'ரத்து',
    'விடு',
  }.contains(normalized)) {
    return CygnusDecision.skip;
  }

  if (normalized.startsWith('no ') &&
      RegExp(r'\b(cancel|skip|leave|retry|need)\b').hasMatch(normalized)) {
    return CygnusDecision.skip;
  }
  if (RegExp(r'\b(skip|leave)\s+(it|this|that)\b').hasMatch(normalized) ||
      RegExp(r"\b(dont|do not)\s+(retry|continue)\b").hasMatch(normalized)) {
    return CygnusDecision.skip;
  }

  return CygnusDecision.none;
}

List<String> splitCygnusInstructions(String input) => input
    .split(RegExp(r'[\n;]+'))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList(growable: false);

class CygnusQueuedInstruction {
  const CygnusQueuedInstruction({
    required this.id,
    required this.text,
    required this.fromVoice,
    this.started = false,
    this.retryCount = 0,
  });

  final String id;
  final String text;
  final bool fromVoice;
  final bool started;
  final int retryCount;

  CygnusQueuedInstruction copyWith({bool? started, int? retryCount}) =>
      CygnusQueuedInstruction(
        id: id,
        text: text,
        fromVoice: fromVoice,
        started: started ?? this.started,
        retryCount: retryCount ?? this.retryCount,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'text': text,
    'fromVoice': fromVoice,
    'started': started,
    'retryCount': retryCount,
  };

  factory CygnusQueuedInstruction.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final text = map['text']?.toString().trim() ?? '';
    if (id.isEmpty || text.isEmpty) {
      throw const FormatException(
        'Queued instruction requires an id and text.',
      );
    }
    final retryCount = map['retryCount'];
    return CygnusQueuedInstruction(
      id: id,
      text: text,
      fromVoice: map['fromVoice'] == true,
      started: map['started'] == true,
      retryCount: retryCount is num
          ? retryCount.toInt().clamp(0, 20).toInt()
          : 0,
    );
  }
}

List<CygnusQueuedInstruction> withoutCygnusInstruction(
  List<CygnusQueuedInstruction> instructions,
  String instructionId,
) => instructions
    .where((instruction) => instruction.id != instructionId)
    .toList(growable: true);
