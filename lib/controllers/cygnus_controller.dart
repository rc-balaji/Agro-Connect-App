import 'dart:async';
import 'dart:math';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../ai/plant_ai_service.dart';
import '../ai/plant_knowledge.dart';
import '../cygnus/cygnus_models.dart';
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
  })  : _store = sessionStore ?? CygnusSessionStore(),
        _voice = voiceService ?? CygnusVoiceService(),
        _plantAi = plantAiService ?? PlantAiService();

  final CygnusSessionStore _store;
  final CygnusVoiceService _voice;
  final PlantAiService _plantAi;

  AgroController? _agro;
  PlanController? _plan;
  GenerativeModel? _model;
  ChatSession? _chat;

  final List<CygnusMessage> _messages = <CygnusMessage>[];
  final List<CygnusSessionSummary> _sessions = <CygnusSessionSummary>[];

  bool _initialized = false;
  bool _busy = false;
  bool _loadingSession = false;
  bool _voiceReply = true;
  bool _listening = false;
  bool _voiceConversation = false;
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
    _chat = null;
    _sessionId = await _store.createSession(languageCode: _languageCode);
    final welcome = _assistantMessage(
      'Hi, I’m Cygnus. You can ask me about your farm, control motors, create plans, check trends, or scan a leaf.',
    );
    _messages.add(welcome);
    await _store.saveMessage(_sessionId!, welcome);
    await _refreshSessions();
    await _rebuildChat();
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
      final match = _sessions.where((s) => s.id == id);
      if (match.isNotEmpty) _languageCode = match.first.languageCode;
      await _rebuildChat();
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
    _chat = null;
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
    await _rebuildChat();
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

    final user = _userMessage(text);
    await _append(user);
    await _ensureSessionTitle(text);

    // Fast deterministic path for explicit immediate motor commands. This
    // reduces latency/quota usage and guarantees that a clear request such as
    // "motor 2 start pannuda" uses the same ACK-verified controller as the
    // manual Motor screen. Timed/scheduled requests deliberately bypass this
    // fast path and go through the conversational agent.
    final fastReply = await _tryFastMotorCommand(text);
    if (fastReply != null) {
      await _append(_assistantMessage(fastReply));
      if (_voiceReply && fromVoice) {
        await _voice.speak(fastReply, _languageCode);
      }
      return;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _ensureChat();
      var response = await _chat!.sendMessage(Content.text(text));

      for (var round = 0; round < 6; round++) {
        final calls = response.functionCalls.toList(growable: false);
        if (calls.isEmpty) break;

        final functionResponses = <FunctionResponse>[];
        for (final call in calls) {
          final result = await _executeTool(call.name, call.args);
          functionResponses.add(
            FunctionResponse(call.name, result, id: call.id),
          );
        }
        response = await _chat!.sendMessage(
          Content.functionResponses(functionResponses),
        );
      }

      var reply = response.text?.trim() ?? '';
      if (reply.isEmpty) {
        reply = 'Done.';
      }
      final assistant = _assistantMessage(reply);
      await _append(assistant);

      if (_voiceReply && fromVoice) {
        await _voice.speak(reply, _languageCode);
      }
    } catch (error, stack) {
      debugPrint('Cygnus request failed: $error\n$stack');
      _error = _friendlyAiError(error);
      final assistant = _assistantMessage(_error!);
      await _append(assistant);
    } finally {
      _busy = false;
      notifyListeners();
      if (fromVoice && _voiceConversation && mountedSafe) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 350), () async {
          if (_voiceConversation && !_busy) await startVoiceInput(keepConversation: true);
        }));
      }
    }
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

      // Inform the chat model using text only; the raw image stays on-device.
      await _ensureChat();
      final contextText = 'Local leaf scan result: crop=${advice.crop}, '
          'condition=${advice.condition}, confidence=${(prediction.confidence * 100).toStringAsFixed(1)}%. '
          'Symptoms=${advice.symptoms.join('; ')}. '
          'Treatment=${advice.treatment.join('; ')}. '
          'Prevention=${advice.prevention.join('; ')}.';
      await _chat!.sendMessage(Content.text(contextText));
    } catch (error) {
      _error = 'I couldn’t analyze that leaf. Try a clear photo with one leaf centered.';
      await _append(_assistantMessage(_error!));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> startVoiceInput({bool keepConversation = false}) async {
    if (_busy || _listening || _disposed) return;
    if (!keepConversation) _voiceConversation = false;
    await _voice.stopSpeaking();
    _voiceDraft = '';
    _listening = true;
    notifyListeners();

    await _voice.startListening(
      languageCode: _languageCode,
      onPartial: (text) {
        _voiceDraft = text;
        notifyListeners();
      },
      onFinal: (text) async {
        _voiceDraft = text;
        _listening = false;
        notifyListeners();
        await sendText(text, fromVoice: true);
      },
    );

    // If recognition never started, reflect the real state.
    if (!_voice.listening && _voiceDraft.isEmpty) {
      _listening = false;
      if (keepConversation) _voiceConversation = false;
      notifyListeners();
    }
  }

  Future<void> stopVoiceInput() async {
    _voiceConversation = false;
    await _voice.stopListening();
    _listening = false;
    notifyListeners();
  }

  Future<void> startVoiceConversation() async {
    if (_disposed || _busy) return;
    _voiceConversation = true;
    notifyListeners();
    await startVoiceInput(keepConversation: true);
  }

  Future<void> stopVoiceConversation() async {
    _voiceConversation = false;
    await _voice.stopListening();
    await _voice.stopSpeaking();
    _listening = false;
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

  Future<void> _ensureChat() async {
    if (_chat != null) return;
    await _rebuildChat();
    if (_chat == null) {
      throw StateError('Cygnus AI session is unavailable.');
    }
  }

  Future<void> _rebuildChat() async {
    try {
      _model = FirebaseAI.googleAI(
        appCheck: FirebaseAppCheck.instance,
        auth: FirebaseAuth.instance,
      ).generativeModel(
        model: const String.fromEnvironment(
          'CYGNUS_MODEL',
          defaultValue: 'gemini-3.8-flash',
        ),
        tools: <Tool>[
          Tool.functionDeclarations(_toolDeclarations()),
        ],
        toolConfig: ToolConfig(
          functionCallingConfig: FunctionCallingConfig.auto(),
        ),
        systemInstruction: Content.system(_systemInstruction()),
        generationConfig: GenerationConfig(
          temperature: 0.25,
          maxOutputTokens: 600,
        ),
      );

      final historyMessages = _messages
          .where((m) =>
              m.kind == 'text' &&
              (m.role == 'user' || m.role == 'assistant'))
          .toList();
      final recent = historyMessages.length > 18
          ? historyMessages.sublist(historyMessages.length - 18)
          : historyMessages;

      final history = <Content>[];
      String? bufferedRole;
      final bufferedText = <String>[];

      void flushBuffered() {
        final role = bufferedRole;
        if (role == null || bufferedText.isEmpty) return;
        final joined = bufferedText.join('\n');
        if (role == 'user') {
          history.add(Content.text(joined));
        } else if (history.isNotEmpty) {
          // Skip a leading assistant welcome; Gemini chat history is rebuilt
          // from the first real user turn.
          history.add(Content.model(<Part>[TextPart(joined)]));
        }
        bufferedText.clear();
      }

      for (final message in recent) {
        if (bufferedRole != message.role) {
          flushBuffered();
          bufferedRole = message.role;
        }
        bufferedText.add(message.text);
      }
      flushBuffered();

      _chat = _model!.startChat(history: history);
    } catch (error, stack) {
      _model = null;
      _chat = null;
      _error = 'Cygnus is not available yet. Your farm controls still work normally.';
      debugPrint('Cygnus model initialization failed: $error\n$stack');
    }
  }

  String _systemInstruction() {
    return '''
You are Cygnus, the built-in intelligent farm assistant for AGRO CONNECT.
Talk naturally and briefly. The user commonly speaks Tamil, Tanglish, English, Hindi, Malayalam or Kannada. Reply in the user's language/style unless they ask for another language. Current preferred language code: $_languageCode.

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

Leaf photos are analyzed locally by the Plant Health model. Use get_last_leaf_result when the user asks follow-up questions about the latest leaf diagnosis. Do not prescribe restricted medicines or give unsafe pesticide dosing; present the bundled care guidance and advise following local product labels/agronomy guidance for chemical treatment.

You may navigate the app using open_page when the user asks to open a page.
''';
  }

  List<FunctionDeclaration> _toolDeclarations() {
    return <FunctionDeclaration>[
      FunctionDeclaration(
        'get_current_context',
        'Get current IST date/time plus device online state. Required for relative schedule times.',
        parameters: const <String, Schema>{},
      ),
      FunctionDeclaration(
        'get_current_status',
        'Get current live farm telemetry and motor states. Set live=true when user wants a continuously updating status card.',
        parameters: <String, Schema>{
          'live': Schema.boolean(description: 'Whether to show a live updating status card.'),
        },
        optionalParameters: const <String>['live'],
      ),
      FunctionDeclaration(
        'get_metric_trend',
        'Get recent trend data for temperature, humidity, soil, or water.',
        parameters: <String, Schema>{
          'metric': Schema.string(description: 'temperature, humidity, soil, or water'),
          'minutes': Schema.integer(description: 'How many recent minutes to inspect.'),
        },
        optionalParameters: const <String>['minutes'],
      ),
      FunctionDeclaration(
        'set_motor',
        'Turn one motor on or off now.',
        parameters: <String, Schema>{
          'motor': Schema.integer(description: 'Motor number 1, 2 or 3.'),
          'state': Schema.boolean(description: 'true=ON, false=OFF'),
        },
      ),
      FunctionDeclaration(
        'set_all_motors',
        'Turn all three motors on or off now.',
        parameters: <String, Schema>{
          'state': Schema.boolean(description: 'true=ON, false=OFF'),
        },
      ),
      FunctionDeclaration(
        'list_schedules',
        'List saved motor schedules, optionally for a single motor.',
        parameters: <String, Schema>{
          'motor': Schema.integer(description: 'Optional motor number 1, 2 or 3.'),
        },
        optionalParameters: const <String>['motor'],
      ),
      FunctionDeclaration(
        'prepare_schedule',
        'Prepare a motor schedule for user confirmation. Date YYYY-MM-DD, time HH:mm:ss in Asia/Kolkata.',
        parameters: <String, Schema>{
          'motor': Schema.integer(description: 'Motor number 1, 2 or 3.'),
          'date': Schema.string(description: 'Start date in YYYY-MM-DD.'),
          'time': Schema.string(description: 'Start time in 24-hour HH:mm:ss.'),
          'durationSec': Schema.integer(description: 'Run duration in seconds.'),
          'repeat': Schema.string(description: 'once, daily, or weekly'),
          'weekdays': Schema.array(
            description: 'For weekly repeat only. Sunday=0 through Saturday=6.',
            items: Schema.integer(),
          ),
          'endDate': Schema.string(description: 'Optional recurrence end date YYYY-MM-DD.'),
          'title': Schema.string(description: 'Short user-friendly plan title.'),
        },
        optionalParameters: const <String>['weekdays', 'endDate', 'title'],
      ),
      FunctionDeclaration(
        'prepare_update_schedule',
        'Prepare changes to an existing motor schedule for user confirmation. Only include fields the user wants changed.',
        parameters: <String, Schema>{
          'scheduleId': Schema.string(description: 'Existing schedule ID.'),
          'title': Schema.string(description: 'Optional new title.'),
          'motor': Schema.integer(description: 'Optional new motor number 1, 2 or 3.'),
          'date': Schema.string(description: 'Optional new start date YYYY-MM-DD.'),
          'time': Schema.string(description: 'Optional new start time HH:mm:ss.'),
          'durationSec': Schema.integer(description: 'Optional new run duration in seconds.'),
          'repeat': Schema.string(description: 'Optional repeat: once, daily, or weekly.'),
          'weekdays': Schema.array(
            description: 'Optional weekdays for weekly repeat. Sunday=0 through Saturday=6.',
            items: Schema.integer(),
          ),
          'endDate': Schema.string(description: 'Optional recurrence end date YYYY-MM-DD. Empty string clears it.'),
          'enabled': Schema.boolean(description: 'Optional enabled state.'),
        },
        optionalParameters: const <String>[
          'title',
          'motor',
          'date',
          'time',
          'durationSec',
          'repeat',
          'weekdays',
          'endDate',
          'enabled',
        ],
      ),
      FunctionDeclaration(
        'confirm_pending_action',
        'Confirm and execute the currently prepared action if the user explicitly says confirm/yes/do it.',
        parameters: const <String, Schema>{},
      ),
      FunctionDeclaration(
        'cancel_pending_action',
        'Cancel the currently prepared action.',
        parameters: const <String, Schema>{},
      ),
      FunctionDeclaration(
        'set_schedule_enabled',
        'Enable or disable an existing schedule by ID.',
        parameters: <String, Schema>{
          'scheduleId': Schema.string(description: 'Schedule ID.'),
          'enabled': Schema.boolean(description: 'true to enable, false to disable.'),
        },
      ),
      FunctionDeclaration(
        'prepare_delete_schedule',
        'Prepare deletion of an existing schedule and ask for confirmation.',
        parameters: <String, Schema>{
          'scheduleId': Schema.string(description: 'Schedule ID.'),
        },
      ),
      FunctionDeclaration(
        'get_last_leaf_result',
        'Get the most recent local Plant Health diagnosis in this chat.',
        parameters: const <String, Schema>{},
      ),
      FunctionDeclaration(
        'open_page',
        'Open an AGRO CONNECT page.',
        parameters: <String, Schema>{
          'page': Schema.string(
            description: 'home, motors, plans, monitor, history, plant_health, cygnus, or settings',
          ),
        },
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
    if (error is QuotaExceeded) {
      return 'Cygnus is busy right now. Your normal farm controls still work — try again shortly.';
    }
    if (error is ServiceApiNotEnabled) {
      return 'Cygnus needs Firebase AI Logic to be enabled for this project.';
    }
    if (error is InvalidApiKey) {
      return 'Cygnus could not verify the Firebase AI configuration.';
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
    super.dispose();
  }
}
