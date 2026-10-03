import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/plant_ai_service.dart';
import '../ai/plant_knowledge.dart';
import '../cygnus/cygnus_models.dart';
import '../cygnus/groq_cygnus_service.dart';
import '../cygnus/cygnus_session_store.dart';
import '../cygnus/cygnus_voice_service.dart';
import '../models/schedule_plan.dart';
import '../models/telemetry.dart';
import 'agro_controller.dart';
import 'plan_controller.dart';

class CygnusController extends ChangeNotifier {
  CygnusController({
    CygnusSessionStore? sessionStore,
    CygnusVoiceService? voiceService,
    PlantAiService? plantAiService,
    GroqCygnusService? aiService,
  })  : _store = sessionStore ?? CygnusSessionStore(),
        _voice = voiceService ?? CygnusVoiceService(),
        _plantAi = plantAiService ?? PlantAiService(),
        _ai = aiService ?? GroqCygnusService();

  final CygnusSessionStore _store;
  final CygnusVoiceService _voice;
  final PlantAiService _plantAi;
  final GroqCygnusService _ai;

  AgroController? _agro;
  PlanController? _plan;

  final List<CygnusMessage> _messages = <CygnusMessage>[];
  final List<CygnusSessionSummary> _sessions = <CygnusSessionSummary>[];

  bool _initialized = false;
  bool _busy = false;
  bool _loadingSession = false;
  bool _voiceReply = false;
  bool _listening = false;
  bool _voiceConversation = false;
  bool _voiceProcessing = false;
  bool _speaking = false;
  double _voiceLevel = 0;
  String _voiceDraft = '';
  String _languageCode = 'en';
  String? _sessionId;
  String? _error;
  PendingCygnusAction? _pendingAction;
  Map<String, dynamic>? _lastLeafResult;

  ValueChanged<String>? navigationHandler;

  List<CygnusMessage> get messages => List.unmodifiable(_messages);
  List<CygnusSessionSummary> get sessions => List.unmodifiable(_sessions);
  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get loadingSession => _loadingSession;
  bool get voiceReply => _voiceReply;
  bool get listening => _listening;
  bool get voiceConversation => _voiceConversation;
  bool get voiceAvailable => _voice.available;
  bool get voiceProcessing => _voiceProcessing;
  bool get speaking => _speaking;
  double get voiceLevel => _voiceLevel;
  String get voiceDraft => _voiceDraft;
  String get languageCode => _languageCode;
  String? get sessionId => _sessionId;
  String? get error => _error;
  PendingCygnusAction? get pendingAction => _pendingAction;
  bool get cloudHistoryEnabled => _store.cloudEnabled;

  void attach(AgroController agro, PlanController plan) {
    _agro = agro;
    _plan = plan;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    notifyListeners();

    await _store.initialize();
    await _voice.initialize();
    await _refreshSessions();

    if (_sessions.isEmpty) {
      await newChat();
    } else {
      await openSession(_sessions.first.id);
    }
  }

  Future<void> _refreshSessions() async {
    final items = await _store.listSessions();
    _sessions
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  Future<void> newChat() async {
    _pendingAction = null;
    _lastLeafResult = null;
    _messages.clear();
    _sessionId = await _store.createSession(languageCode: _languageCode);
    final welcome = _assistantMessage(
      'Hi, I’m Cygnus. You can ask me about your farm, control motors, create plans, check trends, or scan a leaf.',
    );
    _messages.add(welcome);
    await _store.saveMessage(_sessionId!, welcome);
    await _refreshSessions();
    notifyListeners();
  }

  Future<void> openSession(String id) async {
    if (_sessionId == id && _messages.isNotEmpty) return;
    _loadingSession = true;
    notifyListeners();
    try {
      _sessionId = id;
      _pendingAction = null;
      _messages
        ..clear()
        ..addAll(await _store.loadMessages(id));
      _restoreLeafContextFromMessages();
      final match = _sessions.where((s) => s.id == id);
      if (match.isNotEmpty) _languageCode = match.first.languageCode;
    } finally {
      _loadingSession = false;
      notifyListeners();
    }
  }

  Future<void> deleteCurrentSession() async {
    final id = _sessionId;
    if (id == null) return;
    await _store.deleteSession(id);
    _sessionId = null;
    _messages.clear();
    await _refreshSessions();
    if (_sessions.isEmpty) {
      await newChat();
    } else {
      await openSession(_sessions.first.id);
    }
  }

  Future<void> setLanguage(String code) async {
    if (!const {'en', 'ta', 'hi', 'ml', 'kn'}.contains(code)) return;
    _languageCode = code;
    final id = _sessionId;
    if (id != null) {
      await _store.updateSession(sessionId: id, languageCode: code);
    }
    notifyListeners();
  }

  void setVoiceReply(bool enabled) {
    _voiceReply = enabled;
    if (!enabled) _voice.stopSpeaking();
    notifyListeners();
  }

  Future<void> sendText(String rawText, {bool fromVoice = false}) async {
    final text = rawText.trim();
    if (text.isEmpty || _busy) return;
    if (_sessionId == null) await newChat();

    final requestedLanguage = _explicitLanguageRequest(text);
    if (requestedLanguage != null && requestedLanguage != _languageCode) {
      await setLanguage(requestedLanguage);
    }

    final user = _userMessage(text);
    await _append(user);
    await _ensureSessionTitle(text);

    final scopeReply = _localScopeReply(text);
    if (scopeReply != null) {
      await _append(_assistantMessage(scopeReply));
      if (fromVoice) await _handleVoiceReply(scopeReply);
      return;
    }

    // Keep follow-up questions tied to the exact leaf diagnosis from this
    // conversation. This avoids generic advice after the user asks things like
    // "preventive measures?" or "how do I treat this?".
    final leafReply = _leafContextReply(text);
    if (leafReply != null) {
      await _append(_assistantMessage(leafReply));
      if (fromVoice) await _handleVoiceReply(leafReply);
      return;
    }

    // Fast deterministic path for explicit immediate motor commands. This
    // reduces latency/quota usage and guarantees that a clear request such as
    // "motor 2 start pannuda" uses the same ACK-verified controller as the
    // manual Motor screen. Timed/scheduled requests deliberately bypass this
    // fast path and go through the conversational agent.
    final fastReply = await _tryFastMotorCommand(text);
    if (fastReply != null) {
      await _append(_assistantMessage(fastReply));
      if (fromVoice) await _handleVoiceReply(fastReply);
      return;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    String? replyForVoice;
    try {
      final model = _modelFor(text);
      final reasoning = _reasoningEffortFor(text);
      final reply = await _ai.runAgent(
        systemInstruction: _systemInstruction(),
        conversation: _messages,
        tools: _toolDefinitions(),
        executeTool: _executeTool,
        model: model,
        reasoningEffort: reasoning,
      );

      await _append(_assistantMessage(reply));
      replyForVoice = reply;
    } catch (error, stack) {
      debugPrint('Cygnus request failed: $error\n$stack');
      _error = _friendlyAiError(error);
      await _append(_assistantMessage(_error!));
      replyForVoice = _error;
    } finally {
      _busy = false;
      notifyListeners();
    }

    if (fromVoice && replyForVoice != null && mountedSafe) {
      await _handleVoiceReply(replyForVoice);
    }
  }

  Future<void> _handleVoiceReply(String reply) async {
    if (_disposed) return;

    // Normal microphone input behaves like voice typing. It never forces an
    // audio answer unless the user explicitly enabled voice replies.
    if (!_voiceConversation) {
      if (_voiceReply) await _voice.speak(reply, _languageCode);
      _voiceDraft = '';
      notifyListeners();
      return;
    }

    if (!_voiceConversation) return;
    final outcome = await _voice.speakInteractive(
      reply,
      _languageCode,
      onSpeaking: (speaking) {
        if (_disposed) return;
        _speaking = speaking;
        notifyListeners();
      },
      onBargeIn: () async {
        if (_disposed || !_voiceConversation) return;
        _speaking = false;
        notifyListeners();
        await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
      },
    );

    if (_disposed || !_voiceConversation) return;
    _speaking = false;
    notifyListeners();
    if (outcome != CygnusSpeechOutcome.interrupted && !_listening && !_voiceProcessing) {
      await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
    }
  }

  String? _explicitLanguageRequest(String text) {
    final value = text.toLowerCase();
    final asksToSwitch = RegExp(
      r'\b(pesu|pesunga|sollu|solunga|speak|talk|reply|language|bolo|baat|batao|parayu|mathadu|helu)\b',
      caseSensitive: false,
    ).hasMatch(value) ||
        value.contains('பேசு') ||
        value.contains('சொல்லு') ||
        value.contains('बोल') ||
        value.contains('बताओ') ||
        value.contains('പറയ') ||
        value.contains('ಸೇಳು') ||
        value.contains('ಹೇಳು');

    if (!asksToSwitch) return null;
    if (value.contains('tamil') || value.contains('தமிழ்')) return 'ta';
    if (value.contains('english')) return 'en';
    if (value.contains('hindi') || value.contains('हिन्दी') || value.contains('हिंदी')) return 'hi';
    if (value.contains('malayalam') || value.contains('മലയാളം')) return 'ml';
    if (value.contains('kannada') || value.contains('ಕನ್ನಡ')) return 'kn';
    return null;
  }

  String? _localScopeReply(String text) {
    final value = text.toLowerCase();
    final coding = RegExp(
      r'\b(write|create|generate|give|show|make|build)\b.{0,40}\b(python|javascript|java|c\+\+|c#|sql|html|css|flutter code|dart code|program|source code|script)\b',
      caseSensitive: false,
    ).hasMatch(value);
    final genericCoding = RegExp(
      r'\b(python|javascript|java|c\+\+|c#)\b.{0,30}\b(code|program|script)\b',
      caseSensitive: false,
    ).hasMatch(value);
    if (coding || genericCoding) {
      return _languageCode == 'ta'
          ? 'நான் AGRO CONNECT farm assistant. Farm status, motors, plans, plant health மற்றும் app controls பற்றி உதவலாம்; general programming/code requests-க்கு பதில் தர மாட்டேன்.'
          : 'I’m focused on AGRO CONNECT. I can help with farm status, motors, plans, plant health and app controls, but not general programming or code requests.';
    }
    return null;
  }

  void _restoreLeafContextFromMessages() {
    _lastLeafResult = null;
    for (final message in _messages.reversed) {
      if (message.kind == 'leaf_result' && message.payload.isNotEmpty) {
        _lastLeafResult = Map<String, dynamic>.from(message.payload);
        break;
      }
    }
  }

  String? _leafContextReply(String text) {
    final result = _lastLeafResult;
    if (result == null) return null;

    final value = text.toLowerCase().trim();
    final prevention = RegExp(
      r'prevent|prevention|preventive|avoid|stop.*spread|varama|varaama|thadukka|tadukka|தடுப்பு|தடுக்க|வராமல்|रोकथाम|बचाव|प्रतिरोध|തടയ|പ്രതിരോധ|ತಡೆ|ತಡೆಗಟ್ಟ',
      caseSensitive: false,
    ).hasMatch(value);
    final treatment = RegExp(
      r'treat|treatment|care|cure|medicine|remedy|marundhu|marunthu|sari.*panna|சிகிச்சை|மருந்து|उपचार|इलाज|ചികിത്സ|ഔഷധ|ಚಿಕಿತ್ಸೆ|ಔಷಧ',
      caseSensitive: false,
    ).hasMatch(value);
    final symptoms = RegExp(
      r'symptom|sign|identify|how.*know|அறிகுறி|लक्षण|ലക്ഷണം|ಲಕ್ಷಣ',
      caseSensitive: false,
    ).hasMatch(value);
    final refersToLeaf = prevention || treatment || symptoms || RegExp(
      r'\b(this|that|it|leaf|plant|disease|result|adha|adhu|andha|intha|indha|idhoda|adhoda)\b',
      caseSensitive: false,
    ).hasMatch(value);

    if (!refersToLeaf) return null;

    final label = result['label']?.toString();
    if (label == null || label.isEmpty) return null;
    final advice = PlantKnowledge.forLabel(
      label,
      LeafLanguageInfo.fromCode(_languageCode),
    );
    final confidence = (result['confidence'] as num?)?.toDouble();

    String bullets(Iterable<String> items) => items.map((e) => '• $e').join('\n');
    final heading = '${advice.crop} · ${advice.condition}';
    final confidenceLine = confidence == null
        ? ''
        : '\nConfidence: ${(confidence * 100).toStringAsFixed(0)}%';

    if (prevention) {
      return '$heading$confidenceLine\n\n${_leafSectionTitle('prevention')}\n${bullets(advice.prevention)}';
    }
    if (treatment) {
      return '$heading$confidenceLine\n\n${_leafSectionTitle('treatment')}\n${bullets(advice.treatment)}\n\n${advice.note}';
    }
    if (symptoms) {
      return '$heading$confidenceLine\n\n${_leafSectionTitle('symptoms')}\n${bullets(advice.symptoms)}';
    }

    return '$heading$confidenceLine\n\n${_leafSectionTitle('treatment')}\n${bullets(advice.treatment.take(2))}\n\n${_leafSectionTitle('prevention')}\n${bullets(advice.prevention.take(2))}';
  }

  String _leafSectionTitle(String section) {
    const titles = <String, Map<String, String>>{
      'en': <String, String>{
        'prevention': 'Prevention',
        'treatment': 'Care & treatment',
        'symptoms': 'What to look for',
      },
      'ta': <String, String>{
        'prevention': 'தடுப்பு முறைகள்',
        'treatment': 'பராமரிப்பு & சிகிச்சை',
        'symptoms': 'கவனிக்க வேண்டிய அறிகுறிகள்',
      },
      'hi': <String, String>{
        'prevention': 'रोकथाम',
        'treatment': 'देखभाल और उपचार',
        'symptoms': 'ध्यान देने योग्य लक्षण',
      },
      'ml': <String, String>{
        'prevention': 'പ്രതിരോധം',
        'treatment': 'പരിചരണവും ചികിത്സയും',
        'symptoms': 'ശ്രദ്ധിക്കേണ്ട ലക്ഷണങ്ങൾ',
      },
      'kn': <String, String>{
        'prevention': 'ತಡೆಗಟ್ಟುವಿಕೆ',
        'treatment': 'ಆರೈಕೆ ಮತ್ತು ಚಿಕಿತ್ಸೆ',
        'symptoms': 'ಗಮನಿಸಬೇಕಾದ ಲಕ್ಷಣಗಳು',
      },
    };
    return titles[_languageCode]?[section] ?? titles['en']![section]!;
  }

  // ChangeNotifier has no public mounted flag; this protects delayed voice
  // continuations after dispose without depending on widget state.
  bool _disposed = false;
  bool get mountedSafe => !_disposed;

  Future<void> analyzeLeaf(String imagePath) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();

    final user = CygnusMessage(
      id: _id('msg'),
      role: 'user',
      text: 'Check this leaf.',
      kind: 'image',
      payload: <String, dynamic>{'path': imagePath},
      createdAt: DateTime.now(),
    );
    await _append(user);

    try {
      await _plantAi.initialize();
      final prediction = await _plantAi.classifyFile(imagePath);
      final language = LeafLanguageInfo.fromCode(_languageCode);
      final advice = PlantKnowledge.forLabel(prediction.label, language);

      _lastLeafResult = <String, dynamic>{
        'label': prediction.label,
        'crop': advice.crop,
        'condition': advice.condition,
        'confidence': prediction.confidence,
        'symptoms': advice.symptoms,
        'treatment': advice.treatment,
        'prevention': advice.prevention,
        'note': advice.note,
      };

      final resultMessage = CygnusMessage(
        id: _id('msg'),
        role: 'assistant',
        text: '${advice.crop} · ${advice.condition}',
        kind: 'leaf_result',
        payload: Map<String, dynamic>.from(_lastLeafResult!),
        createdAt: DateTime.now(),
      );
      await _append(resultMessage);

      // The raw image and diagnosis stay on-device. Follow-up questions use
      // get_last_leaf_result, so no raw leaf image is uploaded to Cygnus.
    } catch (error) {
      _error = 'I couldn’t analyze that leaf. Try a clear photo with one leaf centered.';
      await _append(_assistantMessage(_error!));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> startVoiceInput({
    bool keepConversation = false,
    bool stopCurrentSpeech = true,
  }) async {
    if (_busy || _listening || _voiceProcessing || _disposed) return;
    if (!keepConversation) _voiceConversation = false;
    if (stopCurrentSpeech) await _voice.stopSpeaking();

    _speaking = false;
    _voiceDraft = '';
    _voiceLevel = 0;
    _voiceProcessing = false;
    _listening = true;
    notifyListeners();

    await _voice.startListening(
      languageCode: _languageCode,
      onPartial: (text) {
        if (_disposed) return;
        _voiceDraft = text;
        notifyListeners();
      },
      onFinal: (text) {
        if (_disposed) return;
        _voiceDraft = text;
        _listening = false;
        _voiceProcessing = false;
        _voiceLevel = 0;
        notifyListeners();
        unawaited(_submitVoiceTranscript(text));
      },
      onError: (message) {
        if (_disposed) return;
        _error = message;
        _voiceDraft = '';
        _listening = false;
        _voiceProcessing = false;
        _voiceLevel = 0;
        notifyListeners();
      },
      onLevel: (level) {
        if (_disposed) return;
        _voiceLevel = level.clamp(0.0, 1.0).toDouble();
        notifyListeners();
      },
      onProcessing: (processing) {
        if (_disposed) return;
        _voiceProcessing = processing;
        if (processing) _listening = false;
        notifyListeners();
      },
    );

    if (!_voice.listening && !_voice.processing && _voiceDraft.isEmpty) {
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> _submitVoiceTranscript(String text) async {
    if (_disposed) return;
    final transcript = text.trim();
    _voiceDraft = '';
    _voiceProcessing = false;
    _listening = false;
    _voiceLevel = 0;
    notifyListeners();
    if (transcript.isEmpty) return;
    await sendText(transcript, fromVoice: true);
  }

  Future<void> stopVoiceInput() async {
    if (_voice.listening) {
      _voiceProcessing = true;
      _listening = false;
      _voiceDraft = 'Understanding your voice…';
      notifyListeners();
      await _voice.finishListening();
      return;
    }
    _listening = false;
    _voiceProcessing = false;
    _voiceLevel = 0;
    _voiceDraft = '';
    notifyListeners();
  }

  Future<void> cancelVoiceInput() async {
    await _voice.cancelListening();
    _listening = false;
    _voiceProcessing = false;
    _voiceLevel = 0;
    _voiceDraft = '';
    notifyListeners();
  }

  Future<void> interruptAssistant() async {
    if (!_voiceConversation) return;
    await _voice.stopSpeaking();
    _speaking = false;
    notifyListeners();
    if (!_listening && !_voiceProcessing && !_busy) {
      await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
    }
  }

  Future<void> startVoiceConversation() async {
    if (_disposed || _busy || _voiceProcessing) return;
    await _voice.cancelListening();
    await _voice.stopSpeaking();
    _listening = false;
    _voiceProcessing = false;
    _speaking = false;
    _voiceDraft = '';
    _voiceLevel = 0;

    // Live interaction is always a fresh conversation, matching the user's
    // expectation that voice mode has its own clean session transcript.
    await newChat();
    _voiceConversation = true;
    notifyListeners();
    await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
  }

  Future<void> stopVoiceConversation() async {
    _voiceConversation = false;
    await _voice.cancelListening();
    await _voice.stopSpeaking();
    _listening = false;
    _voiceProcessing = false;
    _speaking = false;
    _voiceLevel = 0;
    _voiceDraft = '';
    notifyListeners();
  }

  Future<void> confirmPendingAction() async {
    final action = _pendingAction;
    if (action == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final result = await _executePending(action);
      _pendingAction = null;
      await _append(
        _assistantMessage(result['message']?.toString() ?? 'Done.'),
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> cancelPendingAction() async {
    if (_pendingAction == null) return;
    _pendingAction = null;
    await _append(_assistantMessage('Cancelled.'));
    notifyListeners();
  }

  Future<void> _ensureSessionTitle(String firstUserText) async {
    final id = _sessionId;
    if (id == null) return;
    final userCount = _messages.where((m) => m.role == 'user').length;
    if (userCount != 1) return;
    final title = firstUserText.length <= 42
        ? firstUserText
        : '${firstUserText.substring(0, 39)}…';
    await _store.updateSession(sessionId: id, title: title);
    await _refreshSessions();
  }

  String _leafPromptContext() {
    final result = _lastLeafResult;
    if (result == null) return 'none';
    final confidence = (result['confidence'] as num?)?.toDouble();
    final pct = confidence == null
        ? 'unknown'
        : '${(confidence * 100).toStringAsFixed(0)}%';
    return 'label=${result['label']}; crop=${result['crop']}; condition=${result['condition']}; confidence=$pct';
  }

  String _systemInstruction() {
    return '''
You are Cygnus, the built-in intelligent farm agent for AGRO CONNECT.
Talk naturally, briefly and action-first. Do not mention model providers, APIs, tool schemas or internal routing to the end user unless they explicitly ask a technical question. The user commonly speaks Tamil, Tanglish, English, Hindi, Malayalam or Kannada. Reply in the user's language/style unless they ask for another language. Current preferred language code: $_languageCode.

STRICT SCOPE: Cygnus is not a general-purpose chatbot. Only help with AGRO CONNECT, the connected farm/device, live telemetry, motors, schedules/plans, plant health/leaf diagnosis, treatment/prevention guidance already available in the app, app navigation, and practical farming questions directly related to these features. Politely refuse unrelated requests such as programming/code generation, essays, homework, trivia, general writing, unrelated technology support, politics, entertainment, or general knowledge. Never write Python/Java/JavaScript/Dart/Flutter code for the user. Redirect them to what Cygnus can do inside AGRO CONNECT.

VOICE STYLE: In voice/live interaction, keep replies concise and conversational. If the user asks to speak in Tamil, English, Hindi, Malayalam or Kannada, immediately use that language for subsequent replies until changed again. Tanglish is valid user input; understand it naturally without correcting the user.

You can read live farm state and operate only through the provided tools. Never invent temperature, humidity, soil, water, motor states, schedule data, or execution results. Use tools whenever live/current/app-specific information is requested.

Motor mapping:
- Motor 1 = green indicator / led2
- Motor 2 = orange indicator / led3
- Motor 3 = red indicator / led4
The soil-moisture irrigation relay is automatic and separate. Never claim Cygnus manually controls the automatic soil relay.

Immediate motor commands: if the user clearly asks to turn a specific motor on/off now (for example "motor 2 start pannuda"), call set_motor immediately. Do not ask for confirmation for clear immediate motor commands. If motor identity or action is missing, ask one short clarification.

Schedules: for any new schedule, collect motor, date, time, duration and repeat rule. If the user uses relative dates/times such as today/tomorrow/morning/evening, call get_current_context before resolving them. When all fields are available, call prepare_schedule. A prepared schedule is not active until the user confirms the in-chat confirmation card. Do not claim it is saved before confirmation.

For "live" requests, call get_current_status with live=true. For trend/history requests, call get_metric_trend. For schedule lists, call list_schedules. To change an existing plan, identify the correct saved schedule and call prepare_update_schedule; ask a short clarification if more than one schedule could match.

When the user says "adha", "that one", "same motor", or similar, use conversation context. Do not expose internal MQTT/Firebase implementation details unless the user explicitly asks technical questions.

Leaf photos are analyzed locally by the Plant Health model. Use get_last_leaf_result when the user asks follow-up questions about the latest leaf diagnosis. Words such as "this leaf", "that result", "preventive measures", "treatment", "care", or pronouns such as "adha/adhu" refer to the latest leaf result unless the user clearly changes topic. Never replace the scanned diagnosis with generic advice. Do not prescribe restricted medicines or give unsafe pesticide dosing; present the bundled care guidance and advise following local product labels/agronomy guidance for chemical treatment.
Latest local leaf context: ${_leafPromptContext()}.

If a pending action exists, the user can confirm it naturally with phrases such as yes, confirm, do it, pannidu, okay, or cancel it with no/cancel/venam.
Current pending action: ${_pendingAction == null ? 'none' : '${_pendingAction!.title} — ${_pendingAction!.details}'}.

You may navigate the app using open_page when the user asks to open a page.
''';
  }

  List<Map<String, dynamic>> _toolDefinitions() {
    Map<String, dynamic> fn(
      String name,
      String description, {
      Map<String, dynamic> properties = const <String, dynamic>{},
      List<String> required = const <String>[],
    }) {
      return <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': name,
          'description': description,
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': properties,
            'required': required,
            'additionalProperties': false,
          },
        },
      };
    }

    Map<String, dynamic> str(String description) => <String, dynamic>{
          'type': 'string',
          'description': description,
        };
    Map<String, dynamic> integer(String description) => <String, dynamic>{
          'type': 'integer',
          'description': description,
        };
    Map<String, dynamic> boolean(String description) => <String, dynamic>{
          'type': 'boolean',
          'description': description,
        };
    Map<String, dynamic> intArray(String description) => <String, dynamic>{
          'type': 'array',
          'description': description,
          'items': const <String, dynamic>{'type': 'integer'},
        };

    return <Map<String, dynamic>>[
      fn(
        'get_current_context',
        'Get current IST date/time plus device online state. Required for relative schedule times.',
      ),
      fn(
        'get_current_status',
        'Get current live farm telemetry and motor states. Set live=true when the user wants a continuously updating status card.',
        properties: <String, dynamic>{
          'live': boolean('Whether to show a live updating status card.'),
        },
      ),
      fn(
        'get_metric_trend',
        'Get recent trend data for temperature, humidity, soil, or water.',
        properties: <String, dynamic>{
          'metric': str('temperature, humidity, soil, or water'),
          'minutes': integer('How many recent minutes to inspect.'),
        },
        required: const <String>['metric'],
      ),
      fn(
        'set_motor',
        'Turn one motor on or off now.',
        properties: <String, dynamic>{
          'motor': integer('Motor number 1, 2 or 3.'),
          'state': boolean('true=ON, false=OFF'),
        },
        required: const <String>['motor', 'state'],
      ),
      fn(
        'set_all_motors',
        'Turn all three motors on or off now.',
        properties: <String, dynamic>{
          'state': boolean('true=ON, false=OFF'),
        },
        required: const <String>['state'],
      ),
      fn(
        'list_schedules',
        'List saved motor schedules, optionally for a single motor.',
        properties: <String, dynamic>{
          'motor': integer('Optional motor number 1, 2 or 3.'),
        },
      ),
      fn(
        'prepare_schedule',
        'Prepare a motor schedule for user confirmation. Date YYYY-MM-DD, time HH:mm:ss in Asia/Kolkata.',
        properties: <String, dynamic>{
          'motor': integer('Motor number 1, 2 or 3.'),
          'date': str('Start date in YYYY-MM-DD.'),
          'time': str('Start time in 24-hour HH:mm:ss.'),
          'durationSec': integer('Run duration in seconds.'),
          'repeat': str('once, daily, or weekly'),
          'weekdays': intArray('For weekly repeat only. Sunday=0 through Saturday=6.'),
          'endDate': str('Optional recurrence end date YYYY-MM-DD.'),
          'title': str('Short user-friendly plan title.'),
        },
        required: const <String>['motor', 'date', 'time', 'durationSec', 'repeat'],
      ),
      fn(
        'prepare_update_schedule',
        'Prepare changes to an existing motor schedule for user confirmation. Only include fields the user wants changed.',
        properties: <String, dynamic>{
          'scheduleId': str('Existing schedule ID.'),
          'title': str('Optional new title.'),
          'motor': integer('Optional new motor number 1, 2 or 3.'),
          'date': str('Optional new start date YYYY-MM-DD.'),
          'time': str('Optional new start time HH:mm:ss.'),
          'durationSec': integer('Optional new run duration in seconds.'),
          'repeat': str('Optional repeat: once, daily, or weekly.'),
          'weekdays': intArray('Optional weekdays for weekly repeat. Sunday=0 through Saturday=6.'),
          'endDate': str('Optional recurrence end date YYYY-MM-DD. Empty string clears it.'),
          'enabled': boolean('Optional enabled state.'),
        },
        required: const <String>['scheduleId'],
      ),
      fn(
        'confirm_pending_action',
        'Confirm and execute the currently prepared action if the user explicitly says confirm/yes/do it.',
      ),
      fn('cancel_pending_action', 'Cancel the currently prepared action.'),
      fn(
        'set_schedule_enabled',
        'Enable or disable an existing schedule by ID.',
        properties: <String, dynamic>{
          'scheduleId': str('Schedule ID.'),
          'enabled': boolean('true to enable, false to disable.'),
        },
        required: const <String>['scheduleId', 'enabled'],
      ),
      fn(
        'prepare_delete_schedule',
        'Prepare deletion of an existing schedule and ask for confirmation.',
        properties: <String, dynamic>{
          'scheduleId': str('Schedule ID.'),
        },
        required: const <String>['scheduleId'],
      ),
      fn(
        'get_last_leaf_result',
        'Get the most recent local Plant Health diagnosis in this chat.',
      ),
      fn(
        'open_page',
        'Open an AGRO CONNECT page.',
        properties: <String, dynamic>{
          'page': str('home, motors, plans, monitor, history, plant_health, cygnus, or settings'),
        },
        required: const <String>['page'],
      ),
    ];
  }

  Future<Map<String, Object?>> _executeTool(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      case 'get_current_context':
        return _currentContext();
      case 'get_current_status':
        return _currentStatus(live: args['live'] == true);
      case 'get_metric_trend':
        return _metricTrend(
          args['metric']?.toString() ?? 'temperature',
          _asInt(args['minutes']) ?? 10,
        );
      case 'set_motor':
        return _setMotor(_asInt(args['motor']) ?? 0, args['state'] == true);
      case 'set_all_motors':
        return _setAllMotors(args['state'] == true);
      case 'list_schedules':
        return _listSchedules(_asInt(args['motor']));
      case 'prepare_schedule':
        return _prepareSchedule(args);
      case 'prepare_update_schedule':
        return _prepareUpdateSchedule(args);
      case 'confirm_pending_action':
        final action = _pendingAction;
        if (action == null) return <String, Object?>{'ok': false, 'message': 'There is nothing waiting for confirmation.'};
        final result = await _executePending(action);
        _pendingAction = null;
        notifyListeners();
        return result;
      case 'cancel_pending_action':
        _pendingAction = null;
        notifyListeners();
        return <String, Object?>{'ok': true, 'message': 'Pending action cancelled.'};
      case 'set_schedule_enabled':
        return _setScheduleEnabled(args['scheduleId']?.toString() ?? '', args['enabled'] == true);
      case 'prepare_delete_schedule':
        return _prepareDeleteSchedule(args['scheduleId']?.toString() ?? '');
      case 'get_last_leaf_result':
        return _lastLeafResult == null
            ? <String, Object?>{'ok': false, 'message': 'No leaf has been scanned in this chat yet.'}
            : <String, Object?>{'ok': true, ..._jsonSafeMap(_lastLeafResult!)};
      case 'open_page':
        final page = args['page']?.toString() ?? 'home';
        navigationHandler?.call(page);
        return <String, Object?>{'ok': true, 'page': page};
      default:
        return <String, Object?>{'ok': false, 'message': 'Unsupported action: $name'};
    }
  }

  Map<String, Object?> _currentContext() {
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return <String, Object?>{
      'ok': true,
      'timezone': 'Asia/Kolkata',
      'date': _dateKey(nowIst),
      'time': _timeKey(nowIst),
      'isoLocal': '${_dateKey(nowIst)}T${_timeKey(nowIst)}+05:30',
      'deviceOnline': _agro?.deviceOnline ?? false,
    };
  }

  Map<String, Object?> _currentStatus({required bool live}) {
    final agro = _agro;
    if (agro == null) return <String, Object?>{'ok': false, 'message': 'Farm controller is not ready.'};
    final t = agro.telemetry;
    final result = <String, Object?>{
      'ok': true,
      'deviceOnline': agro.deviceOnline,
      'temperatureC': t.temperature,
      'humidityPercent': t.humidity,
      'soilPercent': t.soil,
      'waterPercent': t.waterLevel,
      'autoIrrigation': t.led1,
      'motor1': agro.controls.actual2,
      'motor2': agro.controls.actual3,
      'motor3': agro.controls.actual4,
      'lastSeen': agro.lastSeen?.toIso8601String(),
    };

    if (live) {
      unawaited(_append(CygnusMessage(
        id: _id('msg'),
        role: 'assistant',
        text: 'Live farm status',
        kind: 'live_status',
        payload: const <String, dynamic>{'live': true},
        createdAt: DateTime.now(),
      )));
    }
    return result;
  }

  Map<String, Object?> _metricTrend(String rawMetric, int minutes) {
    final agro = _agro;
    if (agro == null) return <String, Object?>{'ok': false, 'message': 'Farm controller is not ready.'};
    final metric = rawMetric.toLowerCase();
    final safeMinutes = minutes.clamp(1, 1440);
    final since = DateTime.now().subtract(Duration(minutes: safeMinutes));
    final source = agro.history.where((e) => e.receivedAt.isAfter(since)).toList();
    final sampled = _sampleTelemetry(source, 40);
    final points = sampled.map((t) => <String, Object?>{
          'time': t.receivedAt.millisecondsSinceEpoch,
          'value': _metricValue(t, metric),
        }).toList(growable: false);

    unawaited(_append(CygnusMessage(
      id: _id('msg'),
      role: 'assistant',
      text: '${_metricLabel(metric)} trend',
      kind: 'trend',
      payload: <String, dynamic>{
        'metric': metric,
        'minutes': safeMinutes,
        'points': points,
      },
      createdAt: DateTime.now(),
    )));

    if (points.isEmpty) {
      return <String, Object?>{'ok': false, 'message': 'No recent history is available for that metric.'};
    }
    final values = points.map((e) => (e['value'] as num).toDouble()).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    return <String, Object?>{
      'ok': true,
      'metric': metric,
      'minutes': safeMinutes,
      'samples': values.length,
      'min': min,
      'max': max,
      'average': double.parse(avg.toStringAsFixed(2)),
      'latest': values.last,
    };
  }

  Future<Map<String, Object?>> _setMotor(int motor, bool state) async {
    final agro = _agro;
    if (agro == null) return <String, Object?>{'ok': false, 'message': 'Farm controller is not ready.'};
    if (motor < 1 || motor > 3) return <String, Object?>{'ok': false, 'message': 'Motor must be 1, 2 or 3.'};
    if (!agro.deviceOnline) return <String, Object?>{'ok': false, 'message': 'Farm device is offline.'};

    await agro.setMotor(motor, state);
    final confirmed = await _waitForMotor(motor, state);
    return <String, Object?>{
      'ok': confirmed,
      'motor': motor,
      'state': state,
      'confirmed': confirmed,
      'roundTripMs': agro.controls.lastRoundTripMs,
      'message': confirmed
          ? 'Motor $motor ${state ? 'started' : 'stopped'}.'
          : 'Command sent, but the device did not confirm the new state in time.',
    };
  }

  Future<Map<String, Object?>> _setAllMotors(bool state) async {
    final results = <Map<String, Object?>>[];
    for (var motor = 1; motor <= 3; motor++) {
      results.add(await _setMotor(motor, state));
    }
    final allOk = results.every((e) => e['ok'] == true);
    return <String, Object?>{
      'ok': allOk,
      'state': state,
      'results': results,
      'message': allOk
          ? 'All motors ${state ? 'started' : 'stopped'}.'
          : 'Some motors did not confirm the command.',
    };
  }

  Map<String, Object?> _listSchedules(int? motor) {
    final plan = _plan;
    if (plan == null) return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    final list = motor == null
        ? plan.plans
        : plan.plans.where((item) => item.motor == motor).toList();
    final schedules = list.take(30).map((item) => <String, Object?>{
          'id': item.id,
          'title': item.title,
          'motor': item.motor,
          'date': item.date,
          'time': item.time,
          'durationSec': item.durationSec,
          'repeat': item.repeat,
          'weekdays': item.weekdays,
          'endDate': item.endDate,
          'enabled': item.enabled,
          'nextRunAt': item.nextRunAt,
        }).toList(growable: false);
    return <String, Object?>{'ok': true, 'count': schedules.length, 'schedules': schedules};
  }

  Map<String, Object?> _prepareSchedule(Map<String, Object?> args) {
    final motor = _asInt(args['motor']) ?? 0;
    final date = args['date']?.toString() ?? '';
    final time = SchedulePlan.normalizeTime(args['time']?.toString() ?? '');
    final duration = _asInt(args['durationSec']) ?? 0;
    final repeat = args['repeat']?.toString().toLowerCase() ?? 'once';
    final weekdays = (args['weekdays'] is List)
        ? (args['weekdays'] as List)
            .map(_asInt)
            .whereType<int>()
            .where((e) => e >= 0 && e <= 6)
            .toList(growable: false)
        : <int>[];
    final endDate = args['endDate']?.toString();
    final title = args['title']?.toString().trim();

    final validation = _validateSchedule(
      motor: motor,
      date: date,
      time: time,
      durationSec: duration,
      repeat: repeat,
      weekdays: weekdays,
      endDate: endDate,
    );
    if (validation != null) {
      return <String, Object?>{'ok': false, 'message': validation};
    }

    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'create_schedule',
      title: title?.isNotEmpty == true ? title! : 'Motor $motor plan',
      details: 'Motor $motor · ${SchedulePlan.to12Hour(time)} · ${_durationLabel(duration)} · ${_repeatLabel(repeat, weekdays)}',
      arguments: <String, dynamic>{
        'title': title?.isNotEmpty == true ? title : 'Motor $motor plan',
        'motor': motor,
        'date': date,
        'time': time,
        'durationSec': duration,
        'repeat': repeat,
        'weekdays': weekdays,
        'endDate': endDate,
      },
    );
    _pendingAction = action;
    unawaited(_append(CygnusMessage(
      id: _id('msg'),
      role: 'assistant',
      text: 'Ready to create this plan.',
      kind: 'confirmation',
      payload: <String, dynamic>{
        'pendingId': action.id,
        'title': action.title,
        'details': action.details,
      },
      createdAt: DateTime.now(),
    )));
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'requiresConfirmation': true,
      'pendingId': action.id,
      'summary': action.details,
      'message': 'The schedule is prepared and waiting for user confirmation.',
    };
  }

  Map<String, Object?> _prepareUpdateSchedule(Map<String, Object?> args) {
    final plan = _plan;
    if (plan == null) {
      return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    }
    final scheduleId = args['scheduleId']?.toString() ?? '';
    final matches = plan.plans.where((item) => item.id == scheduleId);
    if (matches.isEmpty) {
      return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    }
    final current = matches.first;
    final motor = _asInt(args['motor']) ?? current.motor;
    final date = args.containsKey('date') ? args['date']?.toString() ?? '' : current.date;
    final time = args.containsKey('time')
        ? SchedulePlan.normalizeTime(args['time']?.toString() ?? '')
        : current.time;
    final duration = _asInt(args['durationSec']) ?? current.durationSec;
    final repeat = args.containsKey('repeat')
        ? args['repeat']?.toString().toLowerCase() ?? current.repeat
        : current.repeat;
    final weekdays = args['weekdays'] is List
        ? (args['weekdays'] as List)
            .map(_asInt)
            .whereType<int>()
            .where((e) => e >= 0 && e <= 6)
            .toList(growable: false)
        : current.weekdays;
    final endDate = args.containsKey('endDate')
        ? (args['endDate']?.toString().trim().isNotEmpty == true
            ? args['endDate'].toString().trim()
            : null)
        : current.endDate;
    final title = args['title']?.toString().trim().isNotEmpty == true
        ? args['title'].toString().trim()
        : current.title;
    final enabled = args.containsKey('enabled') ? args['enabled'] == true : current.enabled;

    final validation = _validateSchedule(
      motor: motor,
      date: date,
      time: time,
      durationSec: duration,
      repeat: repeat,
      weekdays: weekdays,
      endDate: endDate,
    );
    if (validation != null) {
      return <String, Object?>{'ok': false, 'message': validation};
    }

    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'update_schedule',
      title: 'Update $title',
      details: 'Motor $motor · ${SchedulePlan.to12Hour(time)} · ${_durationLabel(duration)} · ${_repeatLabel(repeat, weekdays)}',
      arguments: <String, dynamic>{
        'scheduleId': current.id,
        'title': title,
        'motor': motor,
        'date': date,
        'time': time,
        'durationSec': duration,
        'repeat': repeat,
        'weekdays': weekdays,
        'endDate': endDate,
        'enabled': enabled,
      },
    );
    _pendingAction = action;
    unawaited(_append(CygnusMessage(
      id: _id('msg'),
      role: 'assistant',
      text: 'Ready to update this plan.',
      kind: 'confirmation',
      payload: <String, dynamic>{
        'pendingId': action.id,
        'title': action.title,
        'details': action.details,
      },
      createdAt: DateTime.now(),
    )));
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'requiresConfirmation': true,
      'pendingId': action.id,
      'summary': action.details,
      'message': 'The schedule update is prepared and waiting for user confirmation.',
    };
  }

  Map<String, Object?> _prepareDeleteSchedule(String scheduleId) {
    final plan = _plan;
    if (plan == null) return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    final matches = plan.plans.where((item) => item.id == scheduleId);
    if (matches.isEmpty) return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    final item = matches.first;
    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'delete_schedule',
      title: 'Delete ${item.title}',
      details: 'Motor ${item.motor} · ${item.displayTime} · ${item.repeatLabel}',
      arguments: <String, dynamic>{'scheduleId': item.id},
    );
    _pendingAction = action;
    unawaited(_append(CygnusMessage(
      id: _id('msg'),
      role: 'assistant',
      text: 'Confirm schedule deletion.',
      kind: 'confirmation',
      payload: <String, dynamic>{
        'pendingId': action.id,
        'title': action.title,
        'details': action.details,
        'destructive': true,
      },
      createdAt: DateTime.now(),
    )));
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'requiresConfirmation': true,
      'message': 'Deletion is waiting for confirmation.',
    };
  }

  Future<Map<String, Object?>> _setScheduleEnabled(String id, bool enabled) async {
    final plan = _plan;
    if (plan == null) return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    final matches = plan.plans.where((item) => item.id == id);
    if (matches.isEmpty) return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    final ok = await plan.setEnabled(matches.first, enabled);
    return <String, Object?>{
      'ok': ok,
      'enabled': enabled,
      'message': ok
          ? 'Schedule ${enabled ? 'enabled' : 'disabled'}.'
          : (plan.error ?? 'Could not update the schedule.'),
    };
  }

  Future<Map<String, Object?>> _executePending(PendingCygnusAction action) async {
    final plan = _plan;
    if (plan == null) return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};

    if (action.type == 'create_schedule') {
      final a = action.arguments;
      final draft = ScheduleDraft(
        title: a['title']?.toString() ?? 'Motor plan',
        motor: _asInt(a['motor']) ?? 1,
        date: a['date']?.toString() ?? '',
        time: a['time']?.toString() ?? '00:00:00',
        durationSec: _asInt(a['durationSec']) ?? 30,
        repeat: a['repeat']?.toString() ?? 'once',
        weekdays: (a['weekdays'] as List?)?.map(_asInt).whereType<int>().toList() ?? const <int>[],
        endDate: a['endDate']?.toString().isNotEmpty == true ? a['endDate'].toString() : null,
        enabled: true,
      );
      final ok = await plan.create(draft);
      return <String, Object?>{
        'ok': ok,
        'message': ok
            ? '${action.title} is scheduled.'
            : (plan.error ?? 'Could not save the schedule.'),
      };
    }

    if (action.type == 'update_schedule') {
      final a = action.arguments;
      final id = a['scheduleId']?.toString() ?? '';
      final draft = ScheduleDraft(
        title: a['title']?.toString() ?? 'Motor plan',
        motor: _asInt(a['motor']) ?? 1,
        date: a['date']?.toString() ?? '',
        time: a['time']?.toString() ?? '00:00:00',
        durationSec: _asInt(a['durationSec']) ?? 30,
        repeat: a['repeat']?.toString() ?? 'once',
        weekdays: (a['weekdays'] as List?)?.map(_asInt).whereType<int>().toList() ?? const <int>[],
        endDate: a['endDate']?.toString().isNotEmpty == true ? a['endDate'].toString() : null,
        enabled: a['enabled'] != false,
      );
      final ok = await plan.update(id, draft);
      return <String, Object?>{
        'ok': ok,
        'message': ok
            ? '${action.title.replaceFirst('Update ', '')} is updated.'
            : (plan.error ?? 'Could not update the schedule.'),
      };
    }

    if (action.type == 'delete_schedule') {
      final id = action.arguments['scheduleId']?.toString() ?? '';
      final ok = await plan.delete(id);
      return <String, Object?>{
        'ok': ok,
        'message': ok ? 'Schedule deleted.' : (plan.error ?? 'Could not delete the schedule.'),
      };
    }

    return <String, Object?>{'ok': false, 'message': 'Unsupported pending action.'};
  }

  String _modelFor(String text) {
    final normalized = text.toLowerCase();
    final complexCue = RegExp(
      r'(schedule|plan|tomorrow|today|daily|weekly|monday|tuesday|wednesday|thursday|friday|saturday|sunday|trend|history|why|explain|compare|update|delete|disable|enable|after|later|duration|leaf|treatment|prevention)',
    );
    if (text.length > 150 || complexCue.hasMatch(normalized)) {
      return GroqCygnusService.primaryModel;
    }
    return GroqCygnusService.fastModel;
  }

  String _reasoningEffortFor(String text) {
    final normalized = text.toLowerCase();
    if (RegExp(r'(schedule|plan|update|delete|weekly|daily|tomorrow|after|later|trend|compare|why|explain)')
        .hasMatch(normalized)) {
      return 'medium';
    }
    return 'low';
  }

  Future<String?> _tryFastMotorCommand(String text) async {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Any timing/recurrence cue makes this a plan request rather than an
    // immediate control request.
    final planCue = RegExp(
      r'(schedule|tomorrow|naalaik|nalai|நாளை|daily|every day|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon\b|tue\b|wed\b|thu\b|fri\b|sat\b|sun\b|after\b|later\b|\bsec(?:ond)?s?\b|\bmins?\b|minute|hour|நிமிடம்|மணி|\d{1,2}:\d{2})',
    );
    if (planCue.hasMatch(normalized)) return null;

    bool? requestedState;
    if (RegExp(r'\b(off|stop|stopp|niruth|band|close)\b|நிறுத்து|बंद').hasMatch(normalized)) {
      requestedState = false;
    } else if (RegExp(r'\b(on|start|run|open)\b|தொடங்கு|चालू').hasMatch(normalized)) {
      requestedState = true;
    }
    if (requestedState == null) return null;

    final allMotors = RegExp(r'\b(all|ella|ellaa|எல்லா|sabhi)\b').hasMatch(normalized) &&
        RegExp(r'\b(motor|motro|moter|motar)s?\b').hasMatch(normalized);
    if (allMotors) {
      final result = await _setAllMotors(requestedState);
      return result['message']?.toString();
    }

    int? motor;
    final numeric = RegExp(r'\b(?:motor|motro|moter|motar|m)\s*(?:no\.?\s*)?([123])\b').firstMatch(normalized);
    if (numeric != null) motor = int.tryParse(numeric.group(1)!);

    motor ??= RegExp(r'\b(?:motor|motro|moter|motar)\s*(?:one|ஒன்று|ஒண்ணு|ek)\b').hasMatch(normalized) ? 1 : null;
    motor ??= RegExp(r'\b(?:motor|motro|moter|motar)\s*(?:two|இரண்டு|ரெண்டு|do)\b').hasMatch(normalized) ? 2 : null;
    motor ??= RegExp(r'\b(?:motor|motro|moter|motar)\s*(?:three|மூன்று|மூணு|teen)\b').hasMatch(normalized) ? 3 : null;

    // Friendly aliases already visible in the app/prototype.
    if (motor == null && normalized.contains('green')) motor = 1;
    if (motor == null && normalized.contains('orange')) motor = 2;
    if (motor == null && normalized.contains('red')) motor = 3;

    if (motor == null) return null;
    final result = await _setMotor(motor, requestedState);
    return result['message']?.toString();
  }

  Future<bool> _waitForMotor(int motor, bool state) async {
    final agro = _agro;
    if (agro == null) return false;
    bool actual() => switch (motor) {
          1 => agro.controls.actual2,
          2 => agro.controls.actual3,
          3 => agro.controls.actual4,
          _ => false,
        };

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (actual() == state && agro.controls.pendingKey == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return actual() == state;
  }

  String? _validateSchedule({
    required int motor,
    required String date,
    required String time,
    required int durationSec,
    required String repeat,
    required List<int> weekdays,
    String? endDate,
  }) {
    if (motor < 1 || motor > 3) return 'Choose Motor 1, 2 or 3.';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return 'Date must be YYYY-MM-DD.';
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$').hasMatch(time)) return 'Time must be HH:mm:ss.';
    if (durationSec < 1 || durationSec > 86400) return 'Duration must be between 1 second and 24 hours.';
    if (!const {'once', 'daily', 'weekly'}.contains(repeat)) return 'Repeat must be once, daily or weekly.';
    if (repeat == 'weekly' && weekdays.isEmpty) return 'Choose at least one weekday.';
    if (endDate != null && endDate.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(endDate)) {
      return 'End date must be YYYY-MM-DD.';
    }
    return null;
  }

  Future<void> _append(CygnusMessage message) async {
    _messages.add(message);
    final id = _sessionId;
    if (id != null && message.kind != 'image') {
      await _store.saveMessage(id, message);
    }
    notifyListeners();
  }

  CygnusMessage _userMessage(String text) => CygnusMessage(
        id: _id('msg'),
        role: 'user',
        text: text,
        createdAt: DateTime.now(),
      );

  CygnusMessage _assistantMessage(String text) => CygnusMessage(
        id: _id('msg'),
        role: 'assistant',
        text: text,
        createdAt: DateTime.now(),
      );

  String _friendlyAiError(Object error) {
    if (error is GroqCygnusException) {
      if (error.statusCode == 401 || error.code == 'unauthorized') {
        return 'Cygnus could not verify this app session. Reopen the app and try again.';
      }
      if (error.statusCode == 429 || error.code == 'rate_limit') {
        return 'Cygnus is busy right now. Your normal farm controls still work — try again shortly.';
      }
      if (error.code == 'gateway_not_configured') {
        return 'Cygnus AI is not configured on the gateway yet.';
      }
      if (error.code == 'network_error') {
        return 'Cygnus could not reach the AI service. Check your internet connection and try again.';
      }
      if (error.statusCode != null && error.statusCode! >= 500) {
        return 'Cygnus AI is temporarily unavailable. Your farm controls still work normally.';
      }
      return error.message;
    }
    return 'Cygnus couldn’t complete that request. Please try again.';
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List<Telemetry> _sampleTelemetry(List<Telemetry> input, int maxPoints) {
    if (input.length <= maxPoints) return input;
    final step = input.length / maxPoints;
    return List<Telemetry>.generate(
      maxPoints,
      (i) => input[min(input.length - 1, (i * step).floor())],
      growable: false,
    );
  }

  double _metricValue(Telemetry t, String metric) {
    if (metric == 'humidity') return t.humidity;
    if (metric == 'soil') return t.soil;
    if (metric == 'water' || metric == 'waterlevel' || metric == 'water_level') {
      return t.waterLevel;
    }
    return t.temperature;
  }

  String _metricLabel(String metric) {
    if (metric == 'humidity') return 'Humidity';
    if (metric == 'soil') return 'Soil moisture';
    if (metric == 'water' || metric == 'waterlevel' || metric == 'water_level') {
      return 'Water level';
    }
    return 'Temperature';
  }

  String _durationLabel(int seconds) {
    if (seconds < 60) return '$seconds sec';
    if (seconds % 3600 == 0) return '${seconds ~/ 3600} hr';
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '${seconds ~/ 60} min ${seconds % 60} sec';
  }

  String _repeatLabel(String repeat, List<int> weekdays) {
    if (repeat == 'daily') return 'Daily';
    if (repeat == 'weekly') {
      const labels = <int, String>{0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat'};
      return weekdays.map((e) => labels[e] ?? '').where((e) => e.isNotEmpty).join(', ');
    }
    return 'Once';
  }

  Map<String, Object?> _jsonSafeMap(Map<String, dynamic> input) {
    return input.map((key, value) {
      if (value is List) return MapEntry<String, Object?>(key, value.map((e) => e.toString()).toList());
      if (value is num || value is bool || value is String || value == null) {
        return MapEntry<String, Object?>(key, value);
      }
      return MapEntry<String, Object?>(key, value.toString());
    });
  }

  String _dateKey(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _timeKey(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _id(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  @override
  void dispose() {
    _disposed = true;
    _voice.dispose();
    _plantAi.dispose();
    _ai.dispose();
    super.dispose();
  }
}
