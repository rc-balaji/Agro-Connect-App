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

bool needsCygnusScheduleDateClarification(String input) {
  final value = input.toLowerCase();
  final scheduleIntent =
      RegExp(r'\b(schedule|scheduling|scheduled)\b').hasMatch(value) ||
      (RegExp(r'\bplan\b').hasMatch(value) &&
          RegExp(r'\bmotor\b').hasMatch(value)) ||
      value.contains('அட்டவணை');
  if (!scheduleIntent ||
      RegExp(
        r'\b(update|modify|change|edit|delete|remove|disable|enable|list|show|check|view|cancel)\b',
      ).hasMatch(value)) {
    return false;
  }

  final dateMentioned =
      RegExp(
        r'\b(today|tonight|tomorrow|day after tomorrow|yesterday|'
        r'monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
        r'mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
        r'thingal|chevvai|sevvaai|budhan|viyazhan|vyazhan|'
        r'velli|sani|nyayiru|'
        r'in\s+\d+\s+(?:days?|weeks?)|after\s+\d+\s+(?:days?|weeks?)|'
        r'naalai|naalaiku|naalaikku|nalai|naliku|indru)\b',
        caseSensitive: false,
      ).hasMatch(value) ||
      const [
        'இன்று',
        'நாளை',
        'நாளைக்கு',
        'திங்கள்',
        'செவ்வாய்',
        'புதன்',
        'வியாழன்',
        'வெள்ளி',
        'சனி',
        'ஞாயிறு',
        'आज',
        'कल',
        'परसों',
        'सोमवार',
        'मंगलवार',
        'बुधवार',
        'गुरुवार',
        'शुक्रवार',
        'शनिवार',
        'रविवार',
        'ഇന്ന്',
        'നാളെ',
        'തിങ്കളാഴ്ച',
        'ചൊവ്വാഴ്ച',
        'ബുധനാഴ്ച',
        'വ്യാഴാഴ്ച',
        'വെള്ളിയാഴ്ച',
        'ശനിയാഴ്ച',
        'ഞായറാഴ്ച',
        'ಇಂದು',
        'ನಾಳೆ',
        'ಸೋಮವಾರ',
        'ಮಂಗಳವಾರ',
        'ಬುಧವಾರ',
        'ಗುರುವಾರ',
        'ಶುಕ್ರವಾರ',
        'ಶನಿವಾರ',
        'ಭಾನುವಾರ',
      ].any(value.contains) ||
      RegExp(r'\b\d{4}-\d{1,2}-\d{1,2}\b').hasMatch(value) ||
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b').hasMatch(value) ||
      RegExp(
        r'\b\d{1,2}(?:st|nd|rd|th)?\s+'
        r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|'
        r'jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
        r'nov(?:ember)?|dec(?:ember)?)\b|'
        r'\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|'
        r'jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
        r'nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?\b',
        caseSensitive: false,
      ).hasMatch(value);
  return !dateMentioned;
}

bool needsCygnusScheduleMeridiemClarification(String input) {
  final value = input.toLowerCase();
  final scheduleIntent =
      RegExp(r'\b(schedule|scheduling|scheduled)\b').hasMatch(value) ||
      (RegExp(r'\bplan\b').hasMatch(value) &&
          RegExp(r'\bmotor\b').hasMatch(value)) ||
      value.contains('அட்டவணை');
  if (!scheduleIntent) return false;

  final hasMeridiem =
      RegExp(r'\b(?:a\.?m\.?|p\.?m\.?|noon|midnight)\b').hasMatch(value) ||
      const [
        'morning',
        'afternoon',
        'evening',
        'night',
        'காலை',
        'மதியம்',
        'மாலை',
        'இரவு',
        'kaalai',
        'maalai',
        'iravu',
      ].any(value.contains);
  if (hasMeridiem) return false;

  final matches = RegExp(
    r'\b(?:at|around|by)\s+(\d{1,2})(?::([0-5]\d))?\b|'
    r'@\s*(\d{1,2})(?::([0-5]\d))?\b|'
    r'\b(\d{1,2}):([0-5]\d)\b|'
    r'\b(\d{1,2})\s*(?:o.?clock|mani)\b',
    caseSensitive: false,
  ).allMatches(value);
  for (final match in matches) {
    final rawHour = [
      match.group(1),
      match.group(3),
      match.group(5),
      match.group(7),
    ].whereType<String>().first;
    final hour = int.tryParse(rawHour);
    if (hour != null && hour >= 1 && hour <= 12) return true;
  }
  return false;
}

bool isSeparateCygnusInstructionDuringClarification(String input) {
  final value = input.toLowerCase();
  final newSchedule =
      RegExp(
        r'\b(schedule|scheduling|scheduled|create a plan|make a plan)\b',
      ).hasMatch(value) &&
      RegExp(r'\bmotor\s*[1-3]\b').hasMatch(value) &&
      RegExp(
        r'\bat\b|\b\d{1,2}:\d{2}\b|\b\d+\s*(?:min|minutes?|hours?)\b',
      ).hasMatch(value);
  final immediateMotorCommand =
      RegExp(r'\bmotor\s*[1-3]\b').hasMatch(value) &&
      RegExp(
        r'\b(start|stop|turn on|turn off|switch on|switch off)\b',
      ).hasMatch(value);
  final standaloneRequest = RegExp(
    r'^\s*(?:please\s+)?'
    r'(?:check|show|list|open|scan|analy[sz]e|go to|navigate|tell me|'
    r"what(?:'s|\s+is)|how much|status|temperature|humidity|soil|water)\b",
  ).hasMatch(value);
  return newSchedule || immediateMotorCommand || standaloneRequest;
}

class CygnusQueuedInstruction {
  const CygnusQueuedInstruction({
    required this.id,
    required this.text,
    required this.fromVoice,
    this.started = false,
    this.retryCount = 0,
    this.awaitingClarification = false,
    this.clarificationQuestion,
    this.clarificationAnswers = const <String>[],
  });

  final String id;
  final String text;
  final bool fromVoice;
  final bool started;
  final int retryCount;
  final bool awaitingClarification;
  final String? clarificationQuestion;
  final List<String> clarificationAnswers;

  CygnusQueuedInstruction copyWith({
    String? text,
    bool? started,
    int? retryCount,
    bool? fromVoice,
    bool? awaitingClarification,
    String? clarificationQuestion,
    bool clearClarificationQuestion = false,
    List<String>? clarificationAnswers,
  }) => CygnusQueuedInstruction(
    id: id,
    text: text ?? this.text,
    fromVoice: fromVoice ?? this.fromVoice,
    started: started ?? this.started,
    retryCount: retryCount ?? this.retryCount,
    awaitingClarification: awaitingClarification ?? this.awaitingClarification,
    clarificationQuestion: clearClarificationQuestion
        ? null
        : (clarificationQuestion ?? this.clarificationQuestion),
    clarificationAnswers: clarificationAnswers ?? this.clarificationAnswers,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'text': text,
    'fromVoice': fromVoice,
    'started': started,
    'retryCount': retryCount,
    'awaitingClarification': awaitingClarification,
    if (clarificationQuestion != null)
      'clarificationQuestion': clarificationQuestion,
    'clarificationAnswers': clarificationAnswers,
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
      awaitingClarification: map['awaitingClarification'] == true,
      clarificationQuestion: map['clarificationQuestion']?.toString(),
      clarificationAnswers: map['clarificationAnswers'] is List
          ? (map['clarificationAnswers'] as List)
                .whereType<String>()
                .where((answer) => answer.trim().isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

List<CygnusQueuedInstruction> withoutCygnusInstruction(
  List<CygnusQueuedInstruction> instructions,
  String instructionId,
) => instructions
    .where((instruction) => instruction.id != instructionId)
    .toList(growable: true);
