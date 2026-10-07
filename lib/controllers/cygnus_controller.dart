import 'dart:async';
import 'dart:collection';
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
  }) : _store = sessionStore ?? CygnusSessionStore(),
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
  final LinkedList<_CygnusInstructionEntry> _instructionQueue =
      LinkedList<_CygnusInstructionEntry>();
  final Set<String> _cancelledInstructionIds = <String>{};
  Future<void> _queuePersistenceTail = Future<void>.value();
  Completer<void>? _queueDrainCompleter;
  Completer<void>? _busyCompleter;
  int _busyOperationCount = 0;

  bool _initialized = false;
  bool _busy = false;
  bool _processingQueue = false;
  bool _cancellingInstructionQueue = false;
  bool _restoringQueue = false;
  bool _activeInstructionHadSideEffect = false;
  String? _activeToolFailure;
  String? _deferredDecision;
  ({String text, bool fromVoice})? _deferredClarificationAnswer;
  bool _renderingReply = false;
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
  _PendingCygnusRetry? _pendingRetry;
  CygnusQueuedInstruction? _activeInstruction;
  String? _executingInstructionId;
  String? _confirmingActionInstructionId;
  int _completedInstructionCount = 0;
  int _skippedInstructionCount = 0;
  int _instructionBatchSize = 0;
  Map<String, dynamic>? _lastLeafResult;

  ValueChanged<String>? navigationHandler;

  List<CygnusMessage> get messages => List.unmodifiable(_messages);
  List<CygnusSessionSummary> get sessions => List.unmodifiable(_sessions);
  bool get initialized => _initialized;
  bool get busy => _busy;
  bool get hasPendingInstructions =>
      _instructionQueue.isNotEmpty ||
      (_activeInstruction != null &&
          !_cancelledInstructionIds.contains(_activeInstruction!.id)) ||
      _pendingAction != null ||
      _pendingRetry != null;
  bool get cancellingInstructionQueue => _cancellingInstructionQueue;
  void _beginBusyOperation() {
    if (_busyOperationCount == 0) _busyCompleter = Completer<void>();
    _busyOperationCount++;
    _busy = true;
  }

  void _endBusyOperation() {
    if (_busyOperationCount == 0) return;
    _busyOperationCount--;
    if (_busyOperationCount != 0) return;
    _busy = false;
    final completion = _busyCompleter;
    _busyCompleter = null;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  CygnusQueuedInstruction? get _firstQueuedInstruction =>
      _instructionQueue.isEmpty ? null : _instructionQueue.first.instruction;
  List<CygnusQueuedInstruction> get _instructionSnapshot => _instructionQueue
      .map((entry) => entry.instruction)
      .toList(growable: false);

  void _replaceInstructionQueue(
    Iterable<CygnusQueuedInstruction> instructions,
  ) {
    _instructionQueue.clear();
    for (final instruction in instructions) {
      _instructionQueue.add(_CygnusInstructionEntry(instruction));
    }
  }

  void _replaceFirstInstruction(CygnusQueuedInstruction instruction) {
    _instructionQueue.first.unlink();
    _instructionQueue.addFirst(_CygnusInstructionEntry(instruction));
  }

  String? get _blockedInstructionId =>
      _activeInstruction?.id ?? _pendingRetry?.instruction?.id;
  int get queuedInstructionCount => _instructionQueue
      .where((entry) => entry.instruction.id != _blockedInstructionId)
      .length;
  List<String> get queuedInstructions => List.unmodifiable(
    _instructionQueue
        .where((entry) => entry.instruction.id != _blockedInstructionId)
        .map((entry) => entry.instruction.text),
  );
  String? get activeInstruction => _activeInstruction?.text;
  int get completedInstructionCount => _completedInstructionCount;
  int get skippedInstructionCount => _skippedInstructionCount;
  int get instructionBatchSize => _instructionBatchSize;
  double get instructionProgress => _instructionBatchSize == 0
      ? 0
      : ((_completedInstructionCount + _skippedInstructionCount) /
                _instructionBatchSize)
            .clamp(0.0, 1.0)
            .toDouble();
  bool get restoringQueue => _restoringQueue;
  bool get processingInstructionQueue => _processingQueue;
  String? get pendingRetryInstruction => _pendingRetry?.instruction?.text;
  bool get awaitingClarification =>
      _firstQueuedInstruction?.awaitingClarification ?? false;
  String? get clarificationQuestion =>
      _firstQueuedInstruction?.clarificationQuestion;
  List<String> get clarificationOptions {
    final question = clarificationQuestion?.toLowerCase() ?? '';
    if (RegExp(r'\bam\b.*\bpm\b').hasMatch(question)) {
      return const ['AM', 'PM'];
    }
    if (clarificationHasDatePicker ||
        question.contains('weekday') ||
        question.contains('கிழமை')) {
      return const ['Today', 'Tomorrow'];
    }
    if (question.contains('once, daily, or weekly')) {
      return const ['Once', 'Daily', 'Weekly'];
    }
    if (question.contains('which motor') || question.contains('மோட்டார்')) {
      return const ['Motor 1', 'Motor 2', 'Motor 3'];
    }
    if (question.contains('which weekdays') ||
        question.contains('எந்த கிழமைகளில்')) {
      return const ['Monday', 'Wednesday', 'Friday', 'Every day'];
    }
    if (question.contains('how long') ||
        question.contains('duration') ||
        question.contains('எவ்வளவு நேரம்')) {
      return const ['15 minutes', '30 minutes', '1 hour', '2 hours'];
    }
    if (question.contains('once, daily, or weekly') ||
        question.contains('ஒருமுறை, தினமும்')) {
      return const ['Once', 'Daily', 'Weekly'];
    }
    return const [];
  }

  bool get clarificationHasDatePicker => RegExp(
    r'date|तारीख|തീയതി|ದಿನಾಂಕ|தேதி',
  ).hasMatch(clarificationQuestion?.toLowerCase() ?? '');
  bool get clarificationHasTimePicker {
    final question = clarificationQuestion?.toLowerCase() ?? '';
    if (question.contains('how long') ||
        question.contains('duration') ||
        question.contains('எவ்வளவு நேரம்')) {
      return false;
    }
    return RegExp(r'\btime\b|நேரம்|समय|സമയം|ಸമಯ').hasMatch(question);
  }

  bool get renderingReply => _renderingReply;
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
  String? get pendingRetryId => _pendingRetry?.id;
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
    while (true) {
      if (hasPendingInstructions) {
        await cancelInstructionQueue();
        final queueDrain = _queueDrainCompleter;
        if (queueDrain != null) await queueDrain.future;
        continue;
      }
      final operation = _busyCompleter;
      if (!_busy || operation == null) break;
      await operation.future;
    }
    if (_busy || _loadingSession) return;
    await _createNewChat();
  }

  Future<void> _createNewChat() async {
    _pendingAction = null;
    _pendingRetry = null;
    _activeInstruction = null;
    _cancelledInstructionIds.clear();
    _lastLeafResult = null;
    _error = null;
    _completedInstructionCount = 0;
    _skippedInstructionCount = 0;
    _instructionBatchSize = 0;
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

  Future<void> _restoreInstructionQueue() async {
    if (_instructionQueue.isEmpty) return;
    for (final instruction in _instructionSnapshot) {
      final alreadyShown = _messages.any(
        (message) => message.payload['instructionId'] == instruction.id,
      );
      if (!alreadyShown) {
        await _append(
          _userMessage(instruction.text, instructionId: instruction.id),
        );
      }
      for (final answer in instruction.clarificationAnswers) {
        final answerAlreadyShown = _messages.any(
          (message) =>
              message.role == 'user' &&
              message.payload['instructionId'] == instruction.id &&
              message.text == answer,
        );
        if (!answerAlreadyShown) {
          await _append(_userMessage(answer, instructionId: instruction.id));
        }
      }
    }
    final first = _firstQueuedInstruction!;
    _activeInstruction = first.started ? first : null;
    _restoringQueue = true;
    _activeInstructionHadSideEffect = first.started;
    if (first.awaitingClarification) {
      final question = first.clarificationQuestion;
      if (question != null &&
          !_messages.any(
            (message) =>
                message.role == 'assistant' && message.text.trim() == question,
          )) {
        await _append(_assistantMessage(question));
      }
      _restoringQueue = false;
      return;
    }
    try {
      await _offerInstructionRetry(
        first,
        first.started
            ? 'The app was interrupted while this instruction was running. Check the motor or schedule state before retrying.'
            : 'This instruction was saved but had not started before the app closed.',
      );
    } finally {
      _restoringQueue = false;
    }
  }

  Future<void> openSession(String id) async {
    if (_busy ||
        _instructionQueue.isNotEmpty ||
        _pendingAction != null ||
        _pendingRetry != null) {
      return;
    }
    if (_sessionId == id && _messages.isNotEmpty) return;
    _loadingSession = true;
    notifyListeners();
    try {
      _sessionId = id;
      _pendingAction = null;
      _cancelledInstructionIds.clear();
      _messages
        ..clear()
        ..addAll(await _store.loadMessages(id));
      _replaceInstructionQueue(await _store.loadInstructionQueue(id));
      _activeInstruction = null;
      _completedInstructionCount = 0;
      _skippedInstructionCount = 0;
      _instructionBatchSize = _instructionQueue.length;
      _restoreLeafContextFromMessages();
      final match = _sessions.where((s) => s.id == id);
      if (match.isNotEmpty) _languageCode = match.first.languageCode;
    } catch (error, stack) {
      debugPrint('Cygnus session load failed: $error\n$stack');
      _error = 'Could not restore this chat and its pending instructions.';
      await _append(_assistantMessage(_error!));
    } finally {
      _loadingSession = false;
      notifyListeners();
    }
    if (_sessionId == id) await _restoreInstructionQueue();
  }

  Future<void> deleteCurrentSession() async {
    if (_busy ||
        _instructionQueue.isNotEmpty ||
        _pendingAction != null ||
        _pendingRetry != null) {
      return;
    }
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

  Future<void> clearCurrentChat() async {
    if (_loadingSession) return;
    if (hasPendingInstructions) {
      await cancelInstructionQueue();
      final queueDrain = _queueDrainCompleter;
      if (queueDrain != null) await queueDrain.future;
    }
    while (true) {
      if (hasPendingInstructions) {
        await cancelInstructionQueue();
        final queueDrain = _queueDrainCompleter;
        if (queueDrain != null) await queueDrain.future;
        continue;
      }
      final operation = _busyCompleter;
      if (!_busy || operation == null) break;
      await operation.future;
    }
    if (_busy) return;

    final id = _sessionId;
    if (id == null) return;
    await _store.clearSessionMessages(id);
    _messages.clear();
    _pendingAction = null;
    _pendingRetry = null;
    _activeInstruction = null;
    _lastLeafResult = null;
    _error = null;
    _completedInstructionCount = 0;
    _skippedInstructionCount = 0;
    _instructionBatchSize = 0;
    final welcome = _assistantMessage(
      'Hi, I’m Cygnus. You can ask me about your farm, control motors, create plans, check trends, or scan a leaf.',
    );
    _messages.add(welcome);
    await _store.saveMessage(id, welcome);
    await _refreshSessions();
    notifyListeners();
  }

  Future<void> cancelInstructionQueue() async {
    if (_cancellingInstructionQueue || !hasPendingInstructions) return;
    _cancellingInstructionQueue = true;
    try {
      final queue = _instructionSnapshot;
      final cancelledIds = <String>{
        ...queue.map((instruction) => instruction.id),
        if (_activeInstruction != null) _activeInstruction!.id,
        if (_pendingRetry?.instruction != null) _pendingRetry!.instruction!.id,
      };
      _cancelledInstructionIds.addAll(cancelledIds);
      final runningId =
          _executingInstructionId ?? _confirmingActionInstructionId;
      for (final id in cancelledIds) {
        if (id != runningId) _cancelledInstructionIds.remove(id);
      }
      notifyListeners();
      var persisted = true;
      try {
        await _persistInstructionQueue(const <CygnusQueuedInstruction>[]);
      } catch (error, stack) {
        persisted = false;
        debugPrint(
          'Could not persist Cygnus queue cancellation: $error\n$stack',
        );
      }

      _replaceInstructionQueue(const <CygnusQueuedInstruction>[]);
      _pendingAction = null;
      final retry = _pendingRetry;
      _pendingRetry = null;
      if (retry != null) {
        await _resolveRetryMessage(retry.id, 'Cancelled.');
      }
      _skippedInstructionCount += queue.length;
      if (runningId == null) _activeInstruction = null;
      _error = persisted
          ? null
          : 'The instructions were stopped in this chat, but the cancellation could not be saved and may reappear after reopening.';
      await _append(
        _assistantMessage(
          persisted
              ? 'Cancelled the active and queued instructions. Any device command already sent may still take effect; check the device state.'
              : _error!,
        ),
      );
    } finally {
      _cancellingInstructionQueue = false;
      notifyListeners();
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
    if (text.isEmpty) return;
    if (_sessionId == null) await _createNewChat();
    final decision = parseCygnusDecision(text);
    if (_pendingAction != null && decision == CygnusDecision.approve) {
      if (_busy) {
        _deferredDecision = 'confirm';
        return;
      }
      await confirmPendingAction();
      return;
    }
    if (_pendingAction != null && decision == CygnusDecision.skip) {
      if (_busy) {
        _deferredDecision = 'cancel';
        return;
      }
      await cancelPendingAction();
      return;
    }
    if (_pendingRetry != null && decision == CygnusDecision.approve) {
      if (_busy) {
        _deferredDecision = 'retry';
        return;
      }
      await retryFailedInstruction();
      return;
    }
    if (_pendingRetry != null && decision == CygnusDecision.skip) {
      if (_busy) {
        _deferredDecision = 'dismiss';
        return;
      }
      await dismissFailedInstruction();
      return;
    }
    if (awaitingClarification) {
      if (decision == CygnusDecision.skip) {
        if (_busy) {
          _deferredDecision = 'skip_clarification';
          return;
        }
        await _skipClarification();
        return;
      }
      if (_busy) {
        _deferredClarificationAnswer ??= (text: text, fromVoice: fromVoice);
        return;
      }
      final clarificationParts = splitCygnusInstructions(text);
      final additions = clarificationParts
          .where(isSeparateCygnusInstructionDuringClarification)
          .toList(growable: false);
      if (additions.isNotEmpty) {
        final answerParts = clarificationParts
            .where(
              (part) => !isSeparateCygnusInstructionDuringClarification(part),
            )
            .toList(growable: false);
        await _dispatchInstructionSegments(additions, fromVoice: fromVoice);
        if (answerParts.isNotEmpty) {
          await _answerInstructionClarification(
            answerParts.join('\n'),
            fromVoice: fromVoice,
          );
        }
        return;
      }
      await _answerInstructionClarification(text, fromVoice: fromVoice);
      return;
    }

    final instructions = splitCygnusInstructions(text);
    if (instructions.isEmpty) return;
    await _dispatchInstructionSegments(instructions, fromVoice: fromVoice);
  }

  Future<void> _dispatchInstructionSegments(
    List<String> instructions, {
    required bool fromVoice,
  }) async {
    final plans = instructions
        .where(isCygnusPlanInstruction)
        .toList(growable: false);
    final normalRequests = instructions
        .where((instruction) => !isCygnusPlanInstruction(instruction))
        .toList(growable: false);

    if (plans.isNotEmpty) {
      await _queueInstructionSegments(plans, fromVoice: fromVoice);
    }
    for (final instruction in normalRequests) {
      await _runDirectInstruction(instruction, fromVoice: fromVoice);
    }
  }

  Future<void> _runDirectInstruction(
    String text, {
    required bool fromVoice,
  }) async {
    if (_disposed) return;
    if (_sessionId == null) await _createNewChat();
    _beginBusyOperation();
    notifyListeners();
    try {
      await _processInstruction(
        text,
        fromVoice: fromVoice,
        instructionId: _id('direct'),
      );
    } finally {
      _endBusyOperation();
      notifyListeners();
      if (_instructionQueue.isNotEmpty) {
        unawaited(_drainInstructionQueue());
      }
    }
  }

  Future<void> _queueInstructionSegments(
    List<String> instructions, {
    required bool fromVoice,
  }) async {
    if (instructions.isEmpty) return;
    if (_instructionQueue.isEmpty && _activeInstruction == null) {
      _completedInstructionCount = 0;
      _skippedInstructionCount = 0;
      _instructionBatchSize = 0;
    }
    final addedInstructions = instructions
        .map(
          (instruction) => CygnusQueuedInstruction(
            id: _id('instruction'),
            text: instruction,
            fromVoice: fromVoice,
          ),
        )
        .toList(growable: false);
    final addedIds = addedInstructions
        .map((instruction) => instruction.id)
        .toSet();
    for (final instruction in addedInstructions) {
      _instructionQueue.add(_CygnusInstructionEntry(instruction));
    }
    _instructionBatchSize += addedInstructions.length;
    try {
      await _persistInstructionQueue();
    } catch (error, stack) {
      debugPrint('Cygnus instruction queue persistence failed: $error\n$stack');
      for (final entry in _instructionQueue.toList()) {
        if (addedIds.contains(entry.instruction.id)) entry.unlink();
      }
      _instructionBatchSize -= addedInstructions.length;
      _error =
          'Could not save the new instructions. They were removed without running; earlier queued instructions are unchanged.';
      await _append(_assistantMessage(_error!));
      notifyListeners();
      return;
    }
    notifyListeners();
    await _drainInstructionQueue();
  }

  Future<void> _answerInstructionClarification(
    String answer, {
    required bool fromVoice,
  }) async {
    final current = _firstQueuedInstruction;
    if (current == null || !current.awaitingClarification) return;
    final resumed = current.copyWith(
      fromVoice: current.fromVoice || fromVoice,
      awaitingClarification: false,
      clearClarificationQuestion: true,
      clarificationAnswers: [...current.clarificationAnswers, answer],
    );
    _replaceFirstInstruction(resumed);
    _activeInstruction = resumed;
    try {
      await _persistInstructionQueue();
    } catch (error, stack) {
      debugPrint('Could not save clarification response state: $error\n$stack');
      _replaceFirstInstruction(current);
      _activeInstruction = current;
      _error =
          'Could not save your clarification. The instruction is still waiting; please try again.';
      await _append(_assistantMessage(_error!));
      return;
    }
    await _append(_userMessage(answer, instructionId: current.id));
    notifyListeners();
    await _drainInstructionQueue();
  }

  Future<void> _skipClarification() async {
    final instruction = _firstQueuedInstruction;
    if (instruction == null) return;
    _activeInstruction ??= instruction;
    try {
      await _completeActiveInstruction(skipped: true);
      await _append(
        _assistantMessage(
          'Skipped that instruction. Continuing with the next queued item.',
        ),
      );
    } catch (error, stack) {
      debugPrint(
        'Could not skip instruction awaiting clarification: $error\n$stack',
      );
      _error =
          'Could not save the queue update. This instruction is still waiting.';
      await _append(_assistantMessage(_error!));
      return;
    }
    notifyListeners();
    await _drainInstructionQueue();
  }

  Future<void> _persistInstructionQueue([
    List<CygnusQueuedInstruction>? instructions,
  ]) async {
    final id = _sessionId;
    if (id == null) {
      throw StateError(
        'Cannot save queued instructions without an active chat.',
      );
    }
    final snapshot = List<CygnusQueuedInstruction>.of(
      instructions ?? _instructionSnapshot,
    );
    final write = _queuePersistenceTail
        .catchError((Object error) {
          debugPrint('Previous Cygnus queue write failed: $error');
        })
        .then((_) => _store.saveInstructionQueue(id, snapshot));
    _queuePersistenceTail = write;
    await write;
  }

  String _instructionPromptText(CygnusQueuedInstruction instruction) {
    if (instruction.clarificationAnswers.isEmpty) return instruction.text;
    return [
      instruction.text,
      ...instruction.clarificationAnswers.map(
        (answer) => 'Clarification: $answer',
      ),
    ].join('\n');
  }

  Future<void> _drainInstructionQueue() async {
    if (_processingQueue ||
        _busy ||
        _pendingAction != null ||
        _pendingRetry != null ||
        _disposed) {
      return;
    }

    _processingQueue = true;
    final completion = Completer<void>();
    _queueDrainCompleter = completion;
    _beginBusyOperation();
    notifyListeners();
    try {
      while (_instructionQueue.isNotEmpty &&
          _pendingAction == null &&
          _pendingRetry == null &&
          !_firstQueuedInstruction!.awaitingClarification &&
          !_disposed) {
        final instruction = _firstQueuedInstruction!;
        _activeInstruction = instruction.copyWith(started: true);
        _executingInstructionId = instruction.id;
        _replaceFirstInstruction(_activeInstruction!);
        try {
          await _persistInstructionQueue();
        } catch (error, stack) {
          debugPrint(
            'Could not mark queued instruction as active: $error\n$stack',
          );
          _replaceFirstInstruction(instruction);
          _activeInstruction = null;
          _executingInstructionId = null;
          _error =
              'Could not safely start the saved queue. No new action was sent.';
          await _append(_assistantMessage(_error!));
          break;
        }
        notifyListeners();
        try {
          if (_cancelledInstructionIds.contains(instruction.id)) {
            throw const CygnusAgentCancelled();
          }
          _activeInstructionHadSideEffect = false;
          _activeToolFailure = null;
          await _processInstruction(
            _instructionPromptText(instruction),
            fromVoice: instruction.fromVoice,
            instructionId: instruction.id,
          );
          if (_cancelledInstructionIds.contains(instruction.id)) {
            throw const CygnusAgentCancelled();
          }
          if (_pendingAction == null &&
              _pendingRetry == null &&
              !_firstQueuedInstruction!.awaitingClarification) {
            await _completeActiveInstruction();
          }
        } on CygnusAgentCancelled {
          _cancelledInstructionIds.remove(instruction.id);
          _activeInstruction = null;
        } catch (error, stack) {
          debugPrint('Cygnus queued instruction failed: $error\n$stack');
          final message = _friendlyAiError(error);
          if (_pendingAction == null) {
            await _offerInstructionRetry(instruction, message);
          } else {
            await _append(_assistantMessage(message));
          }
        }
        notifyListeners();
      }
    } finally {
      _processingQueue = false;
      _executingInstructionId = null;
      _endBusyOperation();
      notifyListeners();
      if (identical(_queueDrainCompleter, completion)) {
        _queueDrainCompleter = null;
      }
      completion.complete();
      _flushDeferredDecision();
      if (queuedInstructionCount == 0 &&
          _instructionQueue.isEmpty &&
          _pendingAction == null &&
          _pendingRetry == null &&
          _voiceConversation &&
          !_busy &&
          !_listening &&
          !_voiceProcessing) {
        unawaited(
          startVoiceInput(keepConversation: true, stopCurrentSpeech: false),
        );
      }
    }
  }

  Future<void> _completeActiveInstruction({bool skipped = false}) async {
    final active = _activeInstruction;
    if (active == null) return;
    final sessionId = _sessionId;
    if (sessionId == null) {
      throw StateError(
        'Cannot complete an instruction without an active chat.',
      );
    }
    final remaining = withoutCygnusInstruction(_instructionSnapshot, active.id);
    await _persistInstructionQueue(remaining);
    _replaceInstructionQueue(remaining);
    _activeInstruction = null;
    if (skipped) {
      _skippedInstructionCount++;
    } else {
      _completedInstructionCount++;
    }
    notifyListeners();
  }

  Future<void> _skipActiveInstruction() async {
    _activeInstruction ??= _instructionQueue.isNotEmpty
        ? _firstQueuedInstruction
        : null;
    await _completeActiveInstruction(skipped: true);
  }

  Future<void> _processInstruction(
    String text, {
    required bool fromVoice,
    required String instructionId,
    bool appendUserMessage = true,
    int retryCount = 0,
  }) async {
    _throwIfInstructionCancelled(instructionId);
    if (_sessionId == null) await _createNewChat();

    final requestedLanguage = _explicitLanguageRequest(text);
    if (requestedLanguage != null && requestedLanguage != _languageCode) {
      await setLanguage(requestedLanguage);
      _throwIfInstructionCancelled(instructionId);
    }

    final alreadyShown = _messages.any(
      (message) => message.payload['instructionId'] == instructionId,
    );
    if (!alreadyShown) {
      final user = _userMessage(text, instructionId: instructionId);
      await _append(user);
      if (appendUserMessage) await _ensureSessionTitle(text);
      _throwIfInstructionCancelled(instructionId);
    }

    final scopeReply = _localScopeReply(text);
    if (scopeReply != null) {
      await _append(_assistantMessage(scopeReply));
      _throwIfInstructionCancelled(instructionId);
      if (fromVoice) await _handleVoiceReply(scopeReply);
      return;
    }

    // Keep follow-up questions tied to the exact leaf diagnosis from this
    // conversation. This avoids generic advice after the user asks things like
    // "preventive measures?" or "how do I treat this?".
    final leafReply = _leafContextReply(text);
    if (leafReply != null) {
      await _append(_assistantMessage(leafReply));
      _throwIfInstructionCancelled(instructionId);
      if (fromVoice) await _handleVoiceReply(leafReply);
      return;
    }

    if (needsCygnusScheduleDateClarification(text)) {
      await _askScheduleClarification(
        _scheduleDateQuestion(),
        fromVoice: fromVoice,
      );
      _throwIfInstructionCancelled(instructionId);
      return;
    }
    if (needsCygnusScheduleMeridiemClarification(text)) {
      await _askScheduleClarification(
        _scheduleMeridiemQuestion(text),
        fromVoice: fromVoice,
      );
      _throwIfInstructionCancelled(instructionId);
      return;
    }

    // Fast deterministic path for explicit immediate motor commands. This
    // reduces latency/quota usage and guarantees that a clear request such as
    // "motor 2 start pannuda" uses the same ACK-verified controller as the
    // manual Motor screen. Timed/scheduled requests deliberately bypass this
    // fast path and go through the conversational agent.
    _throwIfInstructionCancelled(instructionId);
    final fastReply = await _tryFastMotorCommand(text);
    _throwIfInstructionCancelled(instructionId);
    if (fastReply != null) {
      await _append(_assistantMessage(fastReply));
      if (_activeToolFailure != null && _pendingAction == null) {
        await _offerInstructionRetry(
          _instructionForRetry(
            text,
            instructionId: instructionId,
            fromVoice: fromVoice,
          ),
          _activeToolFailure!,
          retryCount: retryCount,
        );
      }
      if (fromVoice) await _handleVoiceReply(fastReply);
      return;
    }

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
        executeTool: (name, args) => _executeTool(name, args, instructionId),
        model: model,
        reasoningEffort: reasoning,
        isCancelled: () => _cancelledInstructionIds.contains(instructionId),
      );
      if (_cancelledInstructionIds.contains(instructionId)) {
        throw const CygnusAgentCancelled();
      }

      _renderingReply = true;
      notifyListeners();
      await _appendAnimatedAssistant(reply);
      if (_activeToolFailure != null && _pendingAction == null) {
        await _offerInstructionRetry(
          _instructionForRetry(
            text,
            instructionId: instructionId,
            fromVoice: fromVoice,
          ),
          _activeToolFailure!,
          retryCount: retryCount,
        );
      }
      _renderingReply = false;
      notifyListeners();
      replyForVoice = reply;
    } on CygnusAgentCancelled {
      rethrow;
    } catch (error, stack) {
      debugPrint('Cygnus request failed: $error\n$stack');
      _error = _friendlyAiError(error);
      await _append(_assistantMessage(_error!));
      if (_pendingAction == null) {
        await _offerInstructionRetry(
          _instructionForRetry(
            text,
            instructionId: instructionId,
            fromVoice: fromVoice,
          ),
          _error!,
          retryCount: retryCount,
        );
      }
      replyForVoice = _error;
    } finally {
      _renderingReply = false;
      notifyListeners();
    }

    if (fromVoice && replyForVoice != null && mountedSafe) {
      await _handleVoiceReply(replyForVoice);
    }
  }

  void _throwIfInstructionCancelled(String instructionId) {
    if (_cancelledInstructionIds.contains(instructionId)) {
      throw const CygnusAgentCancelled();
    }
  }

  CygnusQueuedInstruction _instructionForRetry(
    String text, {
    required String instructionId,
    required bool fromVoice,
  }) {
    final active = _activeInstruction;
    if (active != null && active.id == instructionId) return active;
    return CygnusQueuedInstruction(
      id: instructionId,
      text: text,
      fromVoice: fromVoice,
    );
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
    if (outcome != CygnusSpeechOutcome.interrupted &&
        !_listening &&
        !_voiceProcessing) {
      if (_instructionQueue.isNotEmpty && !awaitingClarification) return;
      await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
    }
  }

  Future<void> _askScheduleClarification(
    String question, {
    required bool fromVoice,
  }) async {
    await _requestInstructionClarification(question);
    await _appendAnimatedAssistant(question);
    if (fromVoice) await _handleVoiceReply(question);
  }

  String _scheduleDateQuestion() => switch (_languageCode) {
    'ta' => 'இந்த அட்டவணை எந்த தேதி அல்லது கிழமையிலிருந்து தொடங்க வேண்டும்?',
    'hi' => 'यह शेड्यूल किस तारीख या दिन से शुरू होना चाहिए?',
    'ml' => 'ഈ ഷെഡ്യൂൾ ഏത് തീയതി അല്ലെങ്കിൽ ദിവസത്തിൽ നിന്ന് തുടങ്ങണം?',
    'kn' => 'ಈ ವೇಳಾಪಟ್ಟಿ ಯಾವ ದಿನಾಂಕ ಅಥವಾ ವಾರದ ದಿನದಿಂದ ಆರಂಭವಾಗಬೇಕು?',
    _ => 'What date or weekday should this schedule start on?',
  };

  String _scheduleMeridiemQuestion(String text) {
    final match = RegExp(
      r'\b(?:at|around|by)\s+(\d{1,2})(?::([0-5]\d))?\b|'
      r'@\s*(\d{1,2})(?::([0-5]\d))?\b|'
      r'\b(\d{1,2}):([0-5]\d)\b|'
      r'\b(\d{1,2})\s*(?:o.?clock|mani)\b',
      caseSensitive: false,
    ).firstMatch(text.toLowerCase());
    final hourValues = [
      match?.group(1),
      match?.group(3),
      match?.group(5),
      match?.group(7),
    ].whereType<String>();
    final hour = hourValues.isEmpty ? null : int.tryParse(hourValues.first);
    final minuteValues = [
      match?.group(2),
      match?.group(4),
      match?.group(6),
    ].whereType<String>();
    final minute = minuteValues.isEmpty ? null : minuteValues.first;
    final time = hour == null
        ? ''
        : '${hour > 12 ? hour - 12 : hour}${minute == null ? '' : ':$minute'}';
    return switch (_languageCode) {
      'ta' =>
        '${time.isEmpty ? 'இந்த நேரம்' : '$time மணி'} காலை AM-ஆ, மாலை PM-ஆ?',
      'hi' => '${time.isEmpty ? 'यह समय' : '$time बजे'} AM है या PM?',
      'ml' => '${time.isEmpty ? 'ഈ സമയം' : '$time മണി'} AM ആണോ PM ആണോ?',
      'kn' => '${time.isEmpty ? 'ಈ ಸಮಯ' : '$time ಗಂಟೆ'} AM ಅಥವಾ PM?',
      _ =>
        'Did you mean ${time.isEmpty ? 'AM or PM' : '$time AM or $time PM'}?',
    };
  }

  String? _explicitLanguageRequest(String text) {
    final value = text.toLowerCase();
    final asksToSwitch =
        RegExp(
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
    if (value.contains('hindi') ||
        value.contains('हिन्दी') ||
        value.contains('हिंदी'))
      return 'hi';
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
    final refersToLeaf =
        prevention ||
        treatment ||
        symptoms ||
        RegExp(
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

    String bullets(Iterable<String> items) =>
        items.map((e) => '• $e').join('\n');
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
    if (_busy ||
        _instructionQueue.isNotEmpty ||
        _pendingAction != null ||
        _pendingRetry != null) {
      return;
    }
    _beginBusyOperation();
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
    try {
      await _append(user);
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
      _error =
          'I couldn’t analyze that leaf. Try a clear photo with one leaf centered.';
      await _append(_assistantMessage(_error!));
    } finally {
      _endBusyOperation();
      notifyListeners();
      if (_instructionQueue.isNotEmpty) {
        unawaited(_drainInstructionQueue());
      }
    }
  }

  Future<void> startVoiceInput({
    bool keepConversation = false,
    bool stopCurrentSpeech = true,
  }) async {
    if (_listening || _voiceProcessing || _disposed) return;
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
      liveConversation: keepConversation,
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
    if (isCygnusVoiceFiller(transcript)) {
      await _append(_userMessage(transcript));
      if (_voiceConversation && !_disposed) {
        await startVoiceInput(keepConversation: true, stopCurrentSpeech: false);
      }
      return;
    }
    await sendText(transcript, fromVoice: true);
  }

  Future<void> stopVoiceInput() async {
    if (_listening || _voice.listening) {
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
    if (_disposed ||
        _busy ||
        _voiceProcessing ||
        _instructionQueue.isNotEmpty ||
        _pendingAction != null ||
        _pendingRetry != null) {
      return;
    }
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
    final instructionId = _activeInstruction?.id;
    _confirmingActionInstructionId = instructionId;
    _beginBusyOperation();
    notifyListeners();
    try {
      final result = await _executePending(action);
      final message = result['message']?.toString() ?? 'Done.';
      if (result['ok'] == true) {
        _pendingAction = null;
        await _append(_assistantMessage(message));
        await _completeActiveInstruction();
      } else {
        await _offerActionRetry(action, message);
      }
    } catch (error, stack) {
      debugPrint('Cygnus action confirmation failed: $error\n$stack');
      await _offerActionRetry(action, _friendlyAiError(error));
    } finally {
      _endBusyOperation();
      notifyListeners();
      if (instructionId != null) _cancelledInstructionIds.remove(instructionId);
      _confirmingActionInstructionId = null;
      _deferredDecision = null;
    }
    if (_pendingAction == null && _pendingRetry == null) {
      await _drainInstructionQueue();
    }
  }

  Future<void> cancelPendingAction() async {
    if (_pendingAction == null || _busy) return;
    try {
      await _completeActiveInstruction();
      _pendingAction = null;
      await _append(_assistantMessage('Cancelled.'));
    } catch (error, stack) {
      debugPrint('Could not advance the instruction queue: $error\n$stack');
      _error =
          'Could not update the saved queue. The schedule was not confirmed; try again.';
      await _append(_assistantMessage(_error!));
    }
    notifyListeners();
    if (_pendingAction == null) await _drainInstructionQueue();
  }

  Future<void> retryFailedInstruction() async {
    final retry = _pendingRetry;
    if (retry == null) return;
    if (_busy) {
      _deferredDecision = 'retry';
      return;
    }
    _pendingRetry = null;
    _beginBusyOperation();
    _activeInstructionHadSideEffect = false;
    _activeToolFailure = null;
    final retryInstruction = retry.instruction;
    final retryIsQueued =
        retryInstruction != null &&
        _instructionSnapshot.any(
          (instruction) => instruction.id == retryInstruction.id,
        );
    final previousActiveInstruction = _activeInstruction;
    final active = retryIsQueued ? _firstQueuedInstruction : retryInstruction;
    _executingInstructionId = active?.id;
    var cancelled = false;

    try {
      if (active != null) {
        _activeInstruction = active.copyWith(
          started: true,
          retryCount: active.retryCount + 1,
        );
        if (retryIsQueued) {
          _replaceFirstInstruction(_activeInstruction!);
          await _persistInstructionQueue();
        }
      }
      await _resolveRetryMessage(retry.id, 'Retry approved.');
      notifyListeners();
      final action = retry.action;
      if (action != null) {
        if (retryInstruction != null &&
            _cancelledInstructionIds.contains(retryInstruction.id)) {
          throw const CygnusAgentCancelled();
        }
        final result = await _executePending(action);
        if (retryInstruction != null &&
            _cancelledInstructionIds.contains(retryInstruction.id)) {
          throw const CygnusAgentCancelled();
        }
        final message = result['message']?.toString() ?? 'Done.';
        if (result['ok'] == true) {
          _pendingAction = null;
          await _append(_assistantMessage(message));
          if (retryIsQueued) {
            await _completeActiveInstruction();
          } else {
            _activeInstruction = null;
          }
        } else {
          await _offerActionRetry(
            action,
            message,
            retryCount: _activeInstruction?.retryCount ?? retry.retryCount + 1,
          );
        }
      } else {
        final instruction = active ?? retry.instruction!;
        await _processInstruction(
          _instructionPromptText(instruction),
          fromVoice: instruction.fromVoice,
          instructionId: instruction.id,
          appendUserMessage: false,
          retryCount: instruction.retryCount,
        );
        if (_pendingAction == null && _pendingRetry == null) {
          if (retryIsQueued) {
            await _completeActiveInstruction();
          } else {
            _activeInstruction = null;
          }
        }
      }
    } on CygnusAgentCancelled {
      cancelled = true;
      if (retryInstruction != null) {
        _cancelledInstructionIds.remove(retryInstruction.id);
      }
      _pendingRetry = null;
      _activeInstruction = null;
    } catch (error, stack) {
      debugPrint('Cygnus retry failed: $error\n$stack');
      final message = _friendlyAiError(error);
      final action = retry.action;
      if (action != null) {
        await _offerActionRetry(
          action,
          message,
          retryCount: _activeInstruction?.retryCount ?? retry.retryCount + 1,
        );
      } else {
        await _offerInstructionRetry(
          retry.instruction!,
          message,
          retryCount: _activeInstruction?.retryCount ?? retry.retryCount + 1,
        );
      }
    } finally {
      if (cancelled) {
        _activeInstruction = null;
      } else if (!retryIsQueued) {
        _activeInstruction = previousActiveInstruction;
      }
      _executingInstructionId = null;
      _endBusyOperation();
      notifyListeners();
      if (retryInstruction != null) {
        _cancelledInstructionIds.remove(retryInstruction.id);
      }
      _deferredDecision = null;
    }
    if (_pendingAction == null && _pendingRetry == null) {
      await _drainInstructionQueue();
    }
  }

  Future<void> dismissFailedInstruction() async {
    final retry = _pendingRetry;
    if (retry == null) return;
    if (_busy) {
      _deferredDecision = 'dismiss';
      return;
    }
    try {
      final retryInstruction = retry.instruction;
      final retryIsQueued =
          retryInstruction != null &&
          _instructionSnapshot.any(
            (instruction) => instruction.id == retryInstruction.id,
          );
      if (retryIsQueued || retry.action != null) {
        await _skipActiveInstruction();
      }
      _pendingRetry = null;
      if (retry.action != null) _pendingAction = null;
      await _resolveRetryMessage(
        retry.id,
        'Skipped; continuing with the next queued instruction.',
      );
      if (retry.action != null) {
        await _append(_assistantMessage('Schedule action cancelled.'));
      }
    } catch (error, stack) {
      debugPrint('Could not skip queued instruction: $error\n$stack');
      _error =
          'Could not save the queue update. This instruction is still waiting.';
      await _append(_assistantMessage(_error!));
    }
    notifyListeners();
    if (_pendingRetry == null) await _drainInstructionQueue();
  }

  Future<void> _offerInstructionRetry(
    CygnusQueuedInstruction instruction,
    String error, {
    int retryCount = 0,
  }) async {
    await _offerRetry(
      instruction: instruction,
      error: error,
      retryCount: retryCount,
    );
  }

  Future<void> _offerActionRetry(
    PendingCygnusAction action,
    String error, {
    int retryCount = 0,
  }) async {
    await _offerRetry(
      instruction: _activeInstruction,
      action: action,
      error: error,
      retryCount: retryCount,
    );
  }

  Future<void> _offerRetry({
    CygnusQueuedInstruction? instruction,
    PendingCygnusAction? action,
    required String error,
    int retryCount = 0,
  }) async {
    final id = _id('retry');
    final retryInstruction = instruction ?? _activeInstruction;
    final safeRetryCount = max(retryCount, retryInstruction?.retryCount ?? 0);
    _pendingRetry = _PendingCygnusRetry(
      id: id,
      instruction: retryInstruction,
      action: action,
      retryCount: safeRetryCount,
    );
    final target =
        action?.title ??
        instruction?.text ??
        _activeInstruction?.text ??
        'the last instruction';
    final retryError =
        _activeInstructionHadSideEffect &&
            !error.contains('check its state before retrying')
        ? '$error The action may have reached the device already; check its state before retrying.'
        : error;
    await _append(
      CygnusMessage(
        id: _id('msg'),
        role: 'assistant',
        kind: 'retry',
        text: 'Could not complete: $retryError',
        payload: <String, dynamic>{
          'retryId': id,
          'instruction': target,
          'retryCount': safeRetryCount,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _resolveRetryMessage(String id, String status) async {
    final index = _messages.indexWhere(
      (message) => message.kind == 'retry' && message.payload['retryId'] == id,
    );
    if (index < 0) return;
    final previous = _messages[index];
    final resolved = CygnusMessage(
      id: previous.id,
      role: previous.role,
      kind: 'retry',
      text: previous.text,
      payload: <String, dynamic>{...previous.payload, 'resolved': status},
      createdAt: previous.createdAt,
    );
    _messages[index] = resolved;
    final sessionId = _sessionId;
    if (sessionId != null) await _store.saveMessage(sessionId, resolved);
  }

  void _flushDeferredDecision() {
    final decision = _deferredDecision;
    _deferredDecision = null;
    if (decision == 'confirm' && _pendingAction != null) {
      unawaited(confirmPendingAction());
      return;
    } else if (decision == 'cancel' && _pendingAction != null) {
      unawaited(cancelPendingAction());
      return;
    } else if (decision == 'retry' && _pendingRetry != null) {
      unawaited(retryFailedInstruction());
      return;
    } else if (decision == 'dismiss' && _pendingRetry != null) {
      unawaited(dismissFailedInstruction());
      return;
    } else if (decision == 'skip_clarification' && awaitingClarification) {
      unawaited(_skipClarification());
      return;
    }
    final answer = _deferredClarificationAnswer;
    _deferredClarificationAnswer = null;
    if (answer != null && awaitingClarification) {
      unawaited(sendText(answer.text, fromVoice: answer.fromVoice));
    }
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
MULTI-MOTOR COMMANDS: complete the entire instruction before replying. If the user asks for several motor actions in one sentence (for example "motor 1 stop and motor 2 and 3 start"), call set_motor_batch ONCE with every requested motor/action pair. Verify every result and only then reply with one concise summary. Never stop after the first requested motor.
If several separate instructions arrive while you are working, process them in order, finish and verify each instruction before starting the next, and never drop a queued instruction.

Schedules: for any new schedule, collect motor, an explicit calendar date or an unambiguous weekday, time, duration and repeat rule. A time by itself is never enough to infer a date; never silently use today, tomorrow, or any guessed date. If the date or weekday is missing or ambiguous, call request_clarification with one concise question and do not call prepare_schedule. The instruction stays in the FIFO queue while the user answers; use that answer with the same instruction. Resolve relative dates/weekdays only after get_current_context. Validate that the resulting date/time is a real future occurrence before calling prepare_schedule. A prepared schedule is not active until the user confirms the in-chat confirmation card. Do not claim it is saved before confirmation.

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
        'Get current IST date/time plus device online state. Required to resolve relative dates or weekdays before scheduling.',
      ),
      fn(
        'request_clarification',
        'Ask one concise follow-up when a required detail is missing or ambiguous. Use this instead of guessing, especially when a schedule has a time but no explicit date/day. This pauses only the current FIFO instruction until the user answers.',
        properties: <String, dynamic>{
          'question': str(
            'One concise question asking for the missing detail.',
          ),
        },
        required: const <String>['question'],
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
        properties: <String, dynamic>{'state': boolean('true=ON, false=OFF')},
        required: const <String>['state'],
      ),
      fn(
        'set_motor_batch',
        'Execute multiple immediate motor ON/OFF actions as one complete user request. Use this for mixed or multi-motor commands.',
        properties: <String, dynamic>{
          'operations': <String, dynamic>{
            'type': 'array',
            'description':
                'Every requested motor action. Include all requested motors before calling.',
            'minItems': 1,
            'maxItems': 3,
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'motor': <String, dynamic>{
                  'type': 'integer',
                  'description': 'Motor 1, 2 or 3.',
                },
                'state': <String, dynamic>{
                  'type': 'boolean',
                  'description': 'true=ON, false=OFF',
                },
              },
              'required': <String>['motor', 'state'],
              'additionalProperties': false,
            },
          },
        },
        required: const <String>['operations'],
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
        'Prepare one motor schedule for user confirmation only after the user supplied or unambiguously specified a valid future date, time, motor, duration, and repeat rule. Never invent a missing date. If a date/day is missing or unclear, use request_clarification instead. If another schedule is awaiting confirmation, do not replace it. Date YYYY-MM-DD, time HH:mm:ss in Asia/Kolkata.',
        properties: <String, dynamic>{
          'motor': integer('Motor number 1, 2 or 3.'),
          'date': str('Start date in YYYY-MM-DD.'),
          'time': str('Start time in 24-hour HH:mm:ss.'),
          'durationSec': integer('Run duration in seconds.'),
          'repeat': str('once, daily, or weekly'),
          'weekdays': intArray(
            'For weekly repeat only. Sunday=0 through Saturday=6.',
          ),
          'endDate': str('Optional recurrence end date YYYY-MM-DD.'),
          'title': str('Short user-friendly plan title.'),
        },
        required: const <String>[
          'motor',
          'date',
          'time',
          'durationSec',
          'repeat',
        ],
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
          'weekdays': intArray(
            'Optional weekdays for weekly repeat. Sunday=0 through Saturday=6.',
          ),
          'endDate': str(
            'Optional recurrence end date YYYY-MM-DD. Empty string clears it.',
          ),
          'enabled': boolean('Optional enabled state.'),
        },
        required: const <String>['scheduleId'],
      ),
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
        properties: <String, dynamic>{'scheduleId': str('Schedule ID.')},
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
          'page': str(
            'home, motors, plans, monitor, history, plant_health, cygnus, or settings',
          ),
        },
        required: const <String>['page'],
      ),
    ];
  }

  Future<Map<String, Object?>> _requestInstructionClarification(
    String rawQuestion,
  ) async {
    final question = rawQuestion.trim();
    final active = _activeInstruction;
    final first = _firstQueuedInstruction;
    if (question.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'message': 'A clarification question is required.',
      };
    }
    if (active == null || first == null || first.id != active.id) {
      throw StateError(
        'Cannot pause a clarification without the active queue instruction.',
      );
    }

    final waiting = active.copyWith(
      started: true,
      awaitingClarification: true,
      clarificationQuestion: question,
    );
    _replaceFirstInstruction(waiting);
    _activeInstruction = waiting;
    try {
      await _persistInstructionQueue();
    } catch (_) {
      _replaceFirstInstruction(active);
      _activeInstruction = active;
      rethrow;
    }
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'awaitingClarification': true,
      'question': question,
    };
  }

  Future<Map<String, Object?>> _executeTool(
    String name,
    Map<String, Object?> args,
    String instructionId,
  ) async {
    if (_cancelledInstructionIds.contains(instructionId)) {
      throw const CygnusAgentCancelled();
    }
    final result = await _executeToolInternal(name, args);
    if (_cancelledInstructionIds.contains(instructionId)) {
      throw const CygnusAgentCancelled();
    }
    if (result['needsClarification'] == true) {
      return _requestInstructionClarification(
        result['question']?.toString() ??
            'Please clarify the schedule details.',
      );
    }
    if (result['ok'] == false) {
      _activeToolFailure =
          result['message']?.toString() ?? 'The requested action failed.';
    }
    return result;
  }

  Future<Map<String, Object?>> _executeToolInternal(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      case 'get_current_context':
        return _currentContext();
      case 'request_clarification':
        return await _requestInstructionClarification(
          args['question']?.toString() ?? '',
        );
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
      case 'set_motor_batch':
        return _setMotorBatch(args['operations']);
      case 'list_schedules':
        return _listSchedules(_asInt(args['motor']));
      case 'prepare_schedule':
        final instruction = _activeInstruction;
        if (instruction != null &&
            needsCygnusScheduleMeridiemClarification(
              _instructionPromptText(instruction),
            )) {
          return await _requestInstructionClarification(
            _scheduleMeridiemQuestion(_instructionPromptText(instruction)),
          );
        }
        return _prepareSchedule(args);
      case 'prepare_update_schedule':
        return _prepareUpdateSchedule(args);
      case 'set_schedule_enabled':
        return _setScheduleEnabled(
          args['scheduleId']?.toString() ?? '',
          args['enabled'] == true,
        );
      case 'prepare_delete_schedule':
        return _prepareDeleteSchedule(args['scheduleId']?.toString() ?? '');
      case 'get_last_leaf_result':
        return _lastLeafResult == null
            ? <String, Object?>{
                'ok': false,
                'message': 'No leaf has been scanned in this chat yet.',
              }
            : <String, Object?>{'ok': true, ..._jsonSafeMap(_lastLeafResult!)};
      case 'open_page':
        final page = args['page']?.toString() ?? 'home';
        navigationHandler?.call(page);
        return <String, Object?>{'ok': true, 'page': page};
      default:
        return <String, Object?>{
          'ok': false,
          'message': 'Unsupported action: $name',
        };
    }
  }

  Map<String, Object?> _currentContext() {
    final nowIst = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
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
    if (agro == null)
      return <String, Object?>{
        'ok': false,
        'message': 'Farm controller is not ready.',
      };
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
      unawaited(
        _append(
          CygnusMessage(
            id: _id('msg'),
            role: 'assistant',
            text: 'Live farm status',
            kind: 'live_status',
            payload: const <String, dynamic>{'live': true},
            createdAt: DateTime.now(),
          ),
        ),
      );
    }
    return result;
  }

  Map<String, Object?> _metricTrend(String rawMetric, int minutes) {
    final agro = _agro;
    if (agro == null)
      return <String, Object?>{
        'ok': false,
        'message': 'Farm controller is not ready.',
      };
    final metric = rawMetric.toLowerCase();
    final safeMinutes = minutes.clamp(1, 1440);
    final since = DateTime.now().subtract(Duration(minutes: safeMinutes));
    final source = agro.history
        .where((e) => e.receivedAt.isAfter(since))
        .toList();
    final sampled = _sampleTelemetry(source, 40);
    final points = sampled
        .map(
          (t) => <String, Object?>{
            'time': t.receivedAt.millisecondsSinceEpoch,
            'value': _metricValue(t, metric),
          },
        )
        .toList(growable: false);

    unawaited(
      _append(
        CygnusMessage(
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
        ),
      ),
    );

    if (points.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'message': 'No recent history is available for that metric.',
      };
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
    if (agro == null) {
      _activeToolFailure = 'Farm controller is not ready.';
      return <String, Object?>{'ok': false, 'message': _activeToolFailure!};
    }
    if (motor < 1 || motor > 3) {
      _activeToolFailure = 'Motor must be 1, 2 or 3.';
      return <String, Object?>{'ok': false, 'message': _activeToolFailure!};
    }
    if (!agro.deviceOnline) {
      _activeToolFailure = 'Farm device is offline.';
      return <String, Object?>{'ok': false, 'message': _activeToolFailure!};
    }

    _activeInstructionHadSideEffect = true;
    await agro.setMotor(motor, state);
    final confirmed = await _waitForMotor(motor, state);
    if (!confirmed) {
      _activeToolFailure = 'Motor $motor did not confirm the requested state.';
    }
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

  Future<Map<String, Object?>> _setMotorBatch(Object? rawOperations) async {
    if (rawOperations is! List || rawOperations.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'message': 'No motor actions were provided.',
      };
    }

    final requested = <int, bool>{};
    for (final raw in rawOperations.take(3)) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final motor = _asInt(map['motor']);
      if (motor == null || motor < 1 || motor > 3) continue;
      if (map['state'] is! bool) continue;
      requested[motor] = map['state'] == true;
    }

    if (requested.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'message': 'No valid motor actions were provided.',
      };
    }

    final results = <Map<String, Object?>>[];
    for (final entry in requested.entries) {
      results.add(await _setMotor(entry.key, entry.value));
    }

    final allOk = results.every((item) => item['ok'] == true);
    final summary = results
        .map((item) => item['message']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' ');

    return <String, Object?>{
      'ok': allOk,
      'results': results,
      'message': summary.isEmpty
          ? (allOk
                ? 'Motor actions completed.'
                : 'Some motor actions were not confirmed.')
          : summary,
    };
  }

  Map<String, Object?> _listSchedules(int? motor) {
    final plan = _plan;
    if (plan == null)
      return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    final list = motor == null
        ? plan.plans
        : plan.plans.where((item) => item.motor == motor).toList();
    final schedules = list
        .take(30)
        .map(
          (item) => <String, Object?>{
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
          },
        )
        .toList(growable: false);
    return <String, Object?>{
      'ok': true,
      'count': schedules.length,
      'schedules': schedules,
    };
  }

  Map<String, Object?> _prepareSchedule(Map<String, Object?> args) {
    if (_pendingAction != null) {
      return <String, Object?>{
        'ok': false,
        'message':
            'Another schedule action is awaiting confirmation. Finish it before preparing another.',
      };
    }
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
      requireFutureStart: true,
    );
    if (validation != null) {
      return <String, Object?>{
        'ok': false,
        'needsClarification': true,
        'message': validation,
        'question': _scheduleValidationQuestion(validation),
      };
    }

    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'create_schedule',
      title: title?.isNotEmpty == true ? title! : 'Motor $motor plan',
      details:
          'Motor $motor · ${SchedulePlan.to12Hour(time)} · ${_durationLabel(duration)} · ${_repeatLabel(repeat, weekdays)}',
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
    unawaited(
      _append(
        CygnusMessage(
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
        ),
      ),
    );
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
    if (_pendingAction != null) {
      return <String, Object?>{
        'ok': false,
        'message':
            'Another schedule action is awaiting confirmation. Finish it before preparing another.',
      };
    }
    final scheduleId = args['scheduleId']?.toString() ?? '';
    final matches = plan.plans.where((item) => item.id == scheduleId);
    if (matches.isEmpty) {
      return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    }
    final current = matches.first;
    final motor = _asInt(args['motor']) ?? current.motor;
    final date = args.containsKey('date')
        ? args['date']?.toString() ?? ''
        : current.date;
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
    final enabled = args.containsKey('enabled')
        ? args['enabled'] == true
        : current.enabled;

    final validation = _validateSchedule(
      motor: motor,
      date: date,
      time: time,
      durationSec: duration,
      repeat: repeat,
      weekdays: weekdays,
      endDate: endDate,
      requireFutureStart: args.containsKey('date') || args.containsKey('time'),
    );
    if (validation != null) {
      return <String, Object?>{
        'ok': false,
        'needsClarification': true,
        'message': validation,
        'question': _scheduleValidationQuestion(validation),
      };
    }

    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'update_schedule',
      title: 'Update $title',
      details:
          'Motor $motor · ${SchedulePlan.to12Hour(time)} · ${_durationLabel(duration)} · ${_repeatLabel(repeat, weekdays)}',
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
    unawaited(
      _append(
        CygnusMessage(
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
        ),
      ),
    );
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'requiresConfirmation': true,
      'pendingId': action.id,
      'summary': action.details,
      'message':
          'The schedule update is prepared and waiting for user confirmation.',
    };
  }

  Map<String, Object?> _prepareDeleteSchedule(String scheduleId) {
    final plan = _plan;
    if (plan == null)
      return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    if (_pendingAction != null) {
      return <String, Object?>{
        'ok': false,
        'message':
            'Another schedule action is awaiting confirmation. Finish it before preparing another.',
      };
    }
    final matches = plan.plans.where((item) => item.id == scheduleId);
    if (matches.isEmpty)
      return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    final item = matches.first;
    final action = PendingCygnusAction(
      id: _id('pending'),
      type: 'delete_schedule',
      title: 'Delete ${item.title}',
      details:
          'Motor ${item.motor} · ${item.displayTime} · ${item.repeatLabel}',
      arguments: <String, dynamic>{'scheduleId': item.id},
    );
    _pendingAction = action;
    unawaited(
      _append(
        CygnusMessage(
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
        ),
      ),
    );
    notifyListeners();
    return <String, Object?>{
      'ok': true,
      'requiresConfirmation': true,
      'message': 'Deletion is waiting for confirmation.',
    };
  }

  Future<Map<String, Object?>> _setScheduleEnabled(
    String id,
    bool enabled,
  ) async {
    final plan = _plan;
    if (plan == null)
      return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};
    final matches = plan.plans.where((item) => item.id == id);
    if (matches.isEmpty)
      return <String, Object?>{'ok': false, 'message': 'Schedule not found.'};
    _activeInstructionHadSideEffect = true;
    final ok = await plan.setEnabled(matches.first, enabled);
    return <String, Object?>{
      'ok': ok,
      'enabled': enabled,
      'message': ok
          ? 'Schedule ${enabled ? 'enabled' : 'disabled'}.'
          : (plan.error ?? 'Could not update the schedule.'),
    };
  }

  Future<Map<String, Object?>> _executePending(
    PendingCygnusAction action,
  ) async {
    final plan = _plan;
    if (plan == null)
      return <String, Object?>{'ok': false, 'message': 'Plans are not ready.'};

    if (action.type == 'create_schedule') {
      _activeInstructionHadSideEffect = true;
      final a = action.arguments;
      final draft = ScheduleDraft(
        title: a['title']?.toString() ?? 'Motor plan',
        motor: _asInt(a['motor']) ?? 1,
        date: a['date']?.toString() ?? '',
        time: a['time']?.toString() ?? '00:00:00',
        durationSec: _asInt(a['durationSec']) ?? 30,
        repeat: a['repeat']?.toString() ?? 'once',
        weekdays:
            (a['weekdays'] as List?)?.map(_asInt).whereType<int>().toList() ??
            const <int>[],
        endDate: a['endDate']?.toString().isNotEmpty == true
            ? a['endDate'].toString()
            : null,
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
      _activeInstructionHadSideEffect = true;
      final a = action.arguments;
      final id = a['scheduleId']?.toString() ?? '';
      final draft = ScheduleDraft(
        title: a['title']?.toString() ?? 'Motor plan',
        motor: _asInt(a['motor']) ?? 1,
        date: a['date']?.toString() ?? '',
        time: a['time']?.toString() ?? '00:00:00',
        durationSec: _asInt(a['durationSec']) ?? 30,
        repeat: a['repeat']?.toString() ?? 'once',
        weekdays:
            (a['weekdays'] as List?)?.map(_asInt).whereType<int>().toList() ??
            const <int>[],
        endDate: a['endDate']?.toString().isNotEmpty == true
            ? a['endDate'].toString()
            : null,
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
      _activeInstructionHadSideEffect = true;
      final id = action.arguments['scheduleId']?.toString() ?? '';
      final ok = await plan.delete(id);
      return <String, Object?>{
        'ok': ok,
        'message': ok
            ? 'Schedule deleted.'
            : (plan.error ?? 'Could not delete the schedule.'),
      };
    }

    return <String, Object?>{
      'ok': false,
      'message': 'Unsupported pending action.',
    };
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
    if (RegExp(
      r'(schedule|plan|update|delete|weekly|daily|tomorrow|after|later|trend|compare|why|explain)',
    ).hasMatch(normalized)) {
      return 'medium';
    }
    return 'low';
  }

  Future<String?> _tryFastMotorCommand(String text) async {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Any timing/recurrence cue makes this a plan request rather than an
    // immediate control request.
    final planCue = RegExp(
      r'(schedule|tomorrow|naalaik|nalai|நாளை|daily|every day|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon\b|tue\b|wed\b|thu\b|fri\b|sat\b|sun\b|after\b|later\b|\bsec(?:ond)?s?\b|\bmins?\b|minute|hour|நிமிடம்|மணி|\d{1,2}:\d{2}|\b(?:at|around|by)\s+\d{1,2}\b|\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)\b)',
    );
    if (planCue.hasMatch(normalized)) return null;

    final actions = <({int index, bool state})>[];
    final offPattern = RegExp(
      r'\b(off|stop|stopp|stoppa|niruth|niruthu|band|close)\b|நிறுத்து|बंद',
    );
    final onPattern = RegExp(
      r'\b(on|start|startu|starta|run|open|chalu)\b|தொடங்கு|चालू',
    );
    for (final match in offPattern.allMatches(normalized)) {
      actions.add((index: match.start, state: false));
    }
    for (final match in onPattern.allMatches(normalized)) {
      actions.add((index: match.start, state: true));
    }
    actions.sort((a, b) => a.index.compareTo(b.index));
    if (actions.isEmpty) return null;

    // Mixed ON/OFF sentences are sent to the agent's set_motor_batch tool so
    // every requested action is interpreted together and verified as a batch.
    if (actions.map((item) => item.state).toSet().length > 1) return null;

    final allMotors =
        RegExp(r'\b(all|ella|ellaa|எல்லா|sabhi)\b').hasMatch(normalized) &&
        RegExp(
          r'\b(motor|motro|moter|motar|motu|moto|motoru)s?\b',
        ).hasMatch(normalized);
    if (allMotors && actions.length == 1) {
      final result = await _setAllMotors(actions.first.state);
      return result['message']?.toString();
    }

    int? motorFromToken(String token) {
      switch (token.toLowerCase()) {
        case '1':
        case 'one':
        case 'ஒன்று':
        case 'ஒண்ணு':
        case 'onnu':
        case 'ek':
          return 1;
        case '2':
        case 'two':
        case 'இரண்டு':
        case 'ரெண்டு':
        case 'rendu':
        case 'do':
          return 2;
        case '3':
        case 'three':
        case 'மூன்று':
        case 'மூணு':
        case 'moonu':
        case 'munu':
        case 'teen':
          return 3;
      }
      return null;
    }

    final mentions = <({int index, int motor})>[];
    final explicitMotor = RegExp(
      r'\b(?:motor|motro|moter|motar|motu|moto|motoru|m)\s*(?:no\.?\s*)?(1|2|3|one|two|three|onnu|rendu|moonu|munu|ஒன்று|ஒண்ணு|இரண்டு|ரெண்டு|மூன்று|மூணு|ek|do|teen)\b',
      caseSensitive: false,
    );
    for (final match in explicitMotor.allMatches(normalized)) {
      final motor = motorFromToken(match.group(1)!);
      if (motor != null) mentions.add((index: match.start, motor: motor));
    }

    // Handles natural grouped phrases such as "motor 2 and 3 start" or
    // "start motor 2, 3" where the word motor is not repeated.
    final groupedBare = RegExp(
      r'(?:\band\b|&|,|\+)\s*(?:motor\s*)?(1|2|3|one|two|three|onnu|rendu|moonu|munu)\b',
      caseSensitive: false,
    );
    for (final match in groupedBare.allMatches(normalized)) {
      final motor = motorFromToken(match.group(1)!);
      if (motor != null) mentions.add((index: match.start, motor: motor));
    }

    // Friendly visual aliases already shown in the app/prototype.
    for (final alias in <String, int>{
      'green': 1,
      'orange': 2,
      'red': 3,
    }.entries) {
      for (final match in RegExp(
        r'\b' + alias.key + r'\b',
      ).allMatches(normalized)) {
        mentions.add((index: match.start, motor: alias.value));
      }
    }

    if (mentions.isEmpty) return null;
    mentions.sort((a, b) => a.index.compareTo(b.index));

    // Match each mentioned motor with the closest ON/OFF action. This covers
    // mixed commands such as "motor 1 stop and start motor 2 and 3" without
    // silently dropping the later actions.
    final chosen = <int, ({bool state, int distance, int index})>{};
    for (final mention in mentions) {
      var best = actions.first;
      var bestDistance = (best.index - mention.index).abs();
      for (final action in actions.skip(1)) {
        final distance = (action.index - mention.index).abs();
        if (distance < bestDistance) {
          best = action;
          bestDistance = distance;
        }
      }
      final existing = chosen[mention.motor];
      if (existing == null || bestDistance < existing.distance) {
        chosen[mention.motor] = (
          state: best.state,
          distance: bestDistance,
          index: mention.index,
        );
      }
    }

    if (chosen.isEmpty) return null;
    final ordered = chosen.entries.toList()
      ..sort((a, b) => a.value.index.compareTo(b.value.index));

    final messages = <String>[];
    for (final entry in ordered) {
      final result = await _setMotor(entry.key, entry.value.state);
      final message = result['message']?.toString();
      if (message != null && message.isNotEmpty) messages.add(message);
    }

    if (messages.isEmpty) return null;
    return messages.join(' ');
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
    bool requireFutureStart = false,
  }) {
    if (motor < 1 || motor > 3) return 'Choose Motor 1, 2 or 3.';
    if (!_isValidDateKey(date)) return 'Date must be YYYY-MM-DD.';
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$').hasMatch(time))
      return 'Time must be HH:mm:ss.';
    if (durationSec < 1 || durationSec > 86400)
      return 'Duration must be between 1 second and 24 hours.';
    if (!const {'once', 'daily', 'weekly'}.contains(repeat))
      return 'Repeat must be once, daily or weekly.';
    if (repeat == 'weekly' && weekdays.isEmpty)
      return 'Choose at least one weekday.';
    if (endDate != null && endDate.isNotEmpty) {
      if (!_isValidDateKey(endDate)) return 'End date must be YYYY-MM-DD.';
      if (endDate.compareTo(date) < 0) {
        return 'End date cannot be before the start date.';
      }
    }
    if (requireFutureStart) {
      if (!_hasFutureScheduleOccurrence(
        date: date,
        time: time,
        repeat: repeat,
        weekdays: weekdays,
        endDate: endDate,
      )) {
        return 'Choose a future date and time; the requested start has already passed.';
      }
    }
    return null;
  }

  bool _hasFutureScheduleOccurrence({
    required String date,
    required String time,
    required String repeat,
    required List<int> weekdays,
    String? endDate,
  }) {
    final nowUtc = DateTime.now().toUtc();
    final nowIst = nowUtc.add(const Duration(hours: 5, minutes: 30));
    final dateParts = date.split('-').map(int.parse).toList(growable: false);
    final startDate = DateTime.utc(dateParts[0], dateParts[1], dateParts[2]);
    final todayIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day);
    final firstCandidate = startDate.isAfter(todayIst) ? startDate : todayIst;
    final searchDays = repeat == 'daily' ? 1 : 7;
    final timeParts = time.split(':').map(int.parse).toList(growable: false);

    for (var offset = 0; offset <= searchDays; offset++) {
      final candidate = firstCandidate.add(Duration(days: offset));
      final candidateKey = _dateKey(candidate);
      if (candidateKey.compareTo(date) < 0 ||
          (endDate != null &&
              endDate.isNotEmpty &&
              candidateKey.compareTo(endDate) > 0)) {
        continue;
      }
      final occurs = switch (repeat) {
        'once' => candidateKey == date,
        'daily' => true,
        'weekly' => weekdays.contains(candidate.weekday % 7),
        _ => false,
      };
      if (!occurs) continue;

      final startsAtUtc = DateTime.utc(
        candidate.year,
        candidate.month,
        candidate.day,
        timeParts[0],
        timeParts[1],
        timeParts[2],
      ).subtract(const Duration(hours: 5, minutes: 30));
      if (startsAtUtc.isAfter(nowUtc)) return true;
    }
    return false;
  }

  String _scheduleValidationQuestion(String validation) {
    if (validation.startsWith('Date must') ||
        validation.startsWith('Choose a future date')) {
      return _languageCode == 'ta'
          ? 'எந்த எதிர்கால தேதி அல்லது கிழமையை பயன்படுத்த வேண்டும்?'
          : 'What future date or weekday should I use?';
    }
    if (validation.startsWith('End date')) {
      return _languageCode == 'ta'
          ? 'அட்டவணை எப்போது முடிவடைய வேண்டும்?'
          : 'What end date should I use?';
    }
    if (validation.startsWith('Time must')) {
      return _languageCode == 'ta'
          ? 'எந்த நேரத்தில் இயக்க வேண்டும்?'
          : 'What time should the motor run?';
    }
    if (validation.startsWith('Duration')) {
      return _languageCode == 'ta'
          ? 'எவ்வளவு நேரம் இயக்க வேண்டும்?'
          : 'How long should it run?';
    }
    if (validation.startsWith('Repeat')) {
      return _languageCode == 'ta'
          ? 'ஒருமுறை, தினமும் அல்லது வாரந்தோறும் இயக்கவா?'
          : 'Should it run once, daily, or weekly?';
    }
    if (validation.startsWith('Choose at least one weekday')) {
      return _languageCode == 'ta'
          ? 'எந்த கிழமைகளில் இயக்க வேண்டும்?'
          : 'Which weekdays should it run?';
    }
    if (validation.startsWith('Choose Motor')) {
      return _languageCode == 'ta'
          ? 'எந்த மோட்டாரை பயன்படுத்த வேண்டும் (1, 2 அல்லது 3)?'
          : 'Which motor should I use: 1, 2, or 3?';
    }
    return _languageCode == 'ta'
        ? 'அட்டவணை விவரத்தை தெளிவுபடுத்த முடியுமா?'
        : 'Could you clarify that schedule detail?';
  }

  bool _isValidDateKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parts = value.split('-').map(int.parse).toList(growable: false);
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    return date.year == parts[0] &&
        date.month == parts[1] &&
        date.day == parts[2];
  }

  Future<void> _appendAnimatedAssistant(String fullText) async {
    final clean = fullText.trim();
    if (clean.isEmpty) {
      await _append(_assistantMessage('Done.'));
      return;
    }

    final messageId = _id('msg');
    final createdAt = DateTime.now();
    _messages.add(
      CygnusMessage(
        id: messageId,
        role: 'assistant',
        text: '',
        createdAt: createdAt,
      ),
    );
    notifyListeners();

    final chunks = RegExp(r'\S+\s*')
        .allMatches(clean)
        .map((match) => match.group(0) ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    final batchSize = chunks.length <= 36 ? 1 : (chunks.length / 36).ceil();
    final buffer = StringBuffer();
    for (var i = 0; i < chunks.length; i += batchSize) {
      final end = min(chunks.length, i + batchSize);
      for (var j = i; j < end; j++) {
        buffer.write(chunks[j]);
      }
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index < 0 || _disposed) return;
      _messages[index] = CygnusMessage(
        id: messageId,
        role: 'assistant',
        text: buffer.toString().trimRight(),
        createdAt: createdAt,
      );
      notifyListeners();
      if (end < chunks.length) {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
    }

    final index = _messages.indexWhere((message) => message.id == messageId);
    final finalMessage = CygnusMessage(
      id: messageId,
      role: 'assistant',
      text: clean,
      createdAt: createdAt,
    );
    if (index >= 0) _messages[index] = finalMessage;
    final id = _sessionId;
    if (id != null) await _store.saveMessage(id, finalMessage);
    notifyListeners();
  }

  Future<void> _append(CygnusMessage message) async {
    _messages.add(message);
    final id = _sessionId;
    if (id != null && message.kind != 'image') {
      await _store.saveMessage(id, message);
    }
    notifyListeners();
  }

  CygnusMessage _userMessage(String text, {String? instructionId}) =>
      CygnusMessage(
        id: _id('msg'),
        role: 'user',
        text: text,
        payload: <String, dynamic>{
          if (instructionId != null) 'instructionId': instructionId,
        },
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
    if (metric == 'water' ||
        metric == 'waterlevel' ||
        metric == 'water_level') {
      return t.waterLevel;
    }
    return t.temperature;
  }

  String _metricLabel(String metric) {
    if (metric == 'humidity') return 'Humidity';
    if (metric == 'soil') return 'Soil moisture';
    if (metric == 'water' ||
        metric == 'waterlevel' ||
        metric == 'water_level') {
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
      const labels = <int, String>{
        0: 'Sun',
        1: 'Mon',
        2: 'Tue',
        3: 'Wed',
        4: 'Thu',
        5: 'Fri',
        6: 'Sat',
      };
      return weekdays
          .map((e) => labels[e] ?? '')
          .where((e) => e.isNotEmpty)
          .join(', ');
    }
    return 'Once';
  }

  Map<String, Object?> _jsonSafeMap(Map<String, dynamic> input) {
    return input.map((key, value) {
      if (value is List)
        return MapEntry<String, Object?>(
          key,
          value.map((e) => e.toString()).toList(),
        );
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

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  @override
  void dispose() {
    _disposed = true;
    _voice.dispose();
    _plantAi.dispose();
    _ai.dispose();
    super.dispose();
  }
}

class _PendingCygnusRetry {
  const _PendingCygnusRetry({
    required this.id,
    required this.instruction,
    required this.action,
    required this.retryCount,
  });

  final String id;
  final CygnusQueuedInstruction? instruction;
  final PendingCygnusAction? action;
  final int retryCount;
}

base class _CygnusInstructionEntry
    extends LinkedListEntry<_CygnusInstructionEntry> {
  _CygnusInstructionEntry(this.instruction);

  final CygnusQueuedInstruction instruction;
}
