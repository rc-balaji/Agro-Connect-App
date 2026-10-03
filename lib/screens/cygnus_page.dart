import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../controllers/cygnus_controller.dart';
import '../core/app_theme.dart';
import '../cygnus/cygnus_models.dart';

class CygnusPage extends StatefulWidget {
  const CygnusPage({super.key, required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  State<CygnusPage> createState() => _CygnusPageState();
}

class _CygnusPageState extends State<CygnusPage> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  CygnusController? _boundCygnus;
  int _lastMessageCount = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CygnusController>();
    if (!identical(_boundCygnus, controller)) {
      _boundCygnus?.navigationHandler = null;
      _boundCygnus = controller;
      controller.navigationHandler = widget.onNavigate;
    }
  }

  @override
  void dispose() {
    if (identical(_boundCygnus?.navigationHandler, widget.onNavigate)) {
      _boundCygnus?.navigationHandler = null;
    }
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleScroll(int count) {
    if (_lastMessageCount == count) return;
    _lastMessageCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final value = _composer.text.trim();
    if (value.isEmpty) return;
    _composer.clear();
    _focus.requestFocus();
    await context.read<CygnusController>().sendText(value);
  }

  Future<void> _pickLeaf(ImageSource source) async {
    Navigator.of(context).maybePop();
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;
    await context.read<CygnusController>().analyzeLeaf(image.path);
  }

  Future<void> _showAttachmentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Plant check',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Take a clear leaf photo or choose one from your gallery.',
                style: TextStyle(color: AppTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              _SheetAction(
                icon: Icons.camera_alt_rounded,
                title: 'Take leaf photo',
                subtitle: 'Use your camera',
                onTap: () => _pickLeaf(ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _SheetAction(
                icon: Icons.photo_library_rounded,
                title: 'Choose photo',
                subtitle: 'Pick from your gallery',
                onTap: () => _pickLeaf(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSessions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.76,
        child: Consumer<CygnusController>(
          builder: (context, cygnus, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conversations',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Continue where you left off',
                              style: TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          await cygnus.newChat();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: cygnus.sessions.isEmpty
                      ? const Center(
                          child: Text(
                            'No conversations yet',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: cygnus.sessions.length,
                          itemBuilder: (context, index) {
                            final session = cygnus.sessions[index];
                            final selected = session.id == cygnus.sessionId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: ListTile(
                                selected: selected,
                                selectedTileColor: AppTheme.emerald.withValues(
                                  alpha: 0.09,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color:
                                        (selected
                                                ? AppTheme.emerald
                                                : AppTheme.surface2)
                                            .withValues(
                                              alpha: selected ? 0.13 : 1,
                                            ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 19,
                                    color: selected
                                        ? AppTheme.emeraldSoft
                                        : AppTheme.muted,
                                  ),
                                ),
                                title: Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  _relativeTime(session.updatedAt),
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppTheme.emerald,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () async {
                                  await cygnus.openSession(session.id);
                                  if (sheetContext.mounted)
                                    Navigator.pop(sheetContext);
                                },
                              ),
                            );
                          },
                        ),
                ),
                if (cygnus.sessionId != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed =
                              await showDialog<bool>(
                                context: sheetContext,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Delete this chat?'),
                                  content: const Text(
                                    'This conversation will be removed from your history.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                          if (!confirmed) return;
                          await cygnus.deleteCurrentSession();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete current chat'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cygnus = context.watch<CygnusController>();
    final showThinking = cygnus.busy && !cygnus.renderingReply;
    final lastTextLength = cygnus.messages.isEmpty
        ? 0
        : cygnus.messages.last.text.length;
    _scheduleScroll(
      (cygnus.messages.length * 100000) +
          lastTextLength +
          (showThinking ? 1 : 0),
    );

    return Stack(
      children: [
        Column(
          children: [
            _CygnusBar(
              languageCode: cygnus.languageCode,
              voiceReply: cygnus.voiceReply,
              voiceConversation: cygnus.voiceConversation,
              voiceAvailable: cygnus.voiceAvailable,
              onVoiceConversation: cygnus.voiceConversation
                  ? cygnus.stopVoiceConversation
                  : cygnus.startVoiceConversation,
              onSessions: _showSessions,
              onNewChat: cygnus.newChat,
              onVoiceReplyChanged: cygnus.setVoiceReply,
              onLanguageChanged: cygnus.setLanguage,
            ),
            Expanded(
              child: cygnus.loadingSession
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                      itemCount:
                          cygnus.messages.length + (showThinking ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= cygnus.messages.length) {
                          return const _ThinkingBubble();
                        }
                        return _CygnusMessageView(
                          message: cygnus.messages[index],
                          pendingAction: cygnus.pendingAction,
                          busy: cygnus.busy,
                          pendingRetryId: cygnus.pendingRetryId,
                          onConfirm: cygnus.confirmPendingAction,
                          onCancel: cygnus.cancelPendingAction,
                          onRetry: cygnus.retryFailedInstruction,
                          onDismissRetry: cygnus.dismissFailedInstruction,
                          onPrompt: (value) {
                            _composer.text = value;
                            _send();
                          },
                        );
                      },
                    ),
            ),
            if (!cygnus.voiceConversation &&
                (cygnus.listening ||
                    cygnus.voiceProcessing ||
                    cygnus.voiceDraft.isNotEmpty))
              _VoiceStrip(
                text: cygnus.voiceDraft,
                level: cygnus.voiceLevel,
                processing: cygnus.voiceProcessing,
                onStop: cygnus.stopVoiceInput,
                onCancel: cygnus.cancelVoiceInput,
              ),
            _Composer(
              controller: _composer,
              focusNode: _focus,
              busy: cygnus.busy,
              queuedInstructionCount: cygnus.queuedInstructionCount,
              listening: cygnus.listening,
              voiceProcessing: cygnus.voiceProcessing,
              voiceAvailable: cygnus.voiceAvailable,
              onAttach: _showAttachmentSheet,
              onSend: _send,
              onMic: cygnus.listening
                  ? cygnus.stopVoiceInput
                  : cygnus.startVoiceInput,
            ),
          ],
        ),
        if (cygnus.voiceConversation)
          Positioned.fill(
            child: _LiveVoiceExperience(
              messages: cygnus.messages,
              listening: cygnus.listening,
              processing: cygnus.voiceProcessing || cygnus.busy,
              speaking: cygnus.speaking,
              level: cygnus.voiceLevel,
              draft: cygnus.voiceDraft,
              languageCode: cygnus.languageCode,
              onEnd: cygnus.stopVoiceConversation,
              onStopListening: cygnus.stopVoiceInput,
              onCancelListening: cygnus.cancelVoiceInput,
              onInterrupt: cygnus.interruptAssistant,
              onStartListening: () =>
                  cygnus.startVoiceInput(keepConversation: true),
            ),
          ),
        if (cygnus.activeInstruction != null ||
            cygnus.queuedInstructions.isNotEmpty ||
            cygnus.pendingAction != null ||
            cygnus.pendingRetryId != null ||
            cygnus.awaitingClarification ||
            cygnus.restoringQueue)
          Positioned(
            top: 70,
            left: 12,
            right: 12,
            child: _InstructionQueueOverlay(
              active: cygnus.activeInstruction,
              waiting: cygnus.queuedInstructions,
              completed: cygnus.completedInstructionCount,
              skipped: cygnus.skippedInstructionCount,
              total: cygnus.instructionBatchSize,
              progress: cygnus.instructionProgress,
              running: cygnus.processingInstructionQueue || cygnus.busy,
              waitingForConfirmation: cygnus.pendingAction != null,
              waitingForDecision: cygnus.pendingRetryId != null,
              waitingForClarification: cygnus.awaitingClarification,
              clarificationQuestion: cygnus.clarificationQuestion,
              restoring: cygnus.restoringQueue,
              failedInstruction: cygnus.pendingRetryInstruction,
            ),
          ),
      ],
    );
  }
}

class _LiveVoiceExperience extends StatefulWidget {
  const _LiveVoiceExperience({
    required this.messages,
    required this.listening,
    required this.processing,
    required this.speaking,
    required this.level,
    required this.draft,
    required this.languageCode,
    required this.onEnd,
    required this.onStopListening,
    required this.onCancelListening,
    required this.onInterrupt,
    required this.onStartListening,
  });

  final List<CygnusMessage> messages;
  final bool listening;
  final bool processing;
  final bool speaking;
  final double level;
  final String draft;
  final String languageCode;
  final Future<void> Function() onEnd;
  final Future<void> Function() onStopListening;
  final Future<void> Function() onCancelListening;
  final Future<void> Function() onInterrupt;
  final Future<void> Function() onStartListening;

  @override
  State<_LiveVoiceExperience> createState() => _LiveVoiceExperienceState();
}

class _LiveVoiceExperienceState extends State<_LiveVoiceExperience>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  String get _stateLabel {
    if (widget.speaking) return 'Cygnus is speaking';
    if (widget.processing) return 'Thinking…';
    if (widget.listening) return 'Listening…';
    return 'Ready when you are';
  }

  Color get _stateColor {
    if (widget.speaking) return const Color(0xFF83B7FF);
    if (widget.processing) return AppTheme.amber;
    if (widget.listening) return AppTheme.emeraldSoft;
    return AppTheme.muted;
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = widget.messages
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
    final recent = visibleMessages.length <= 6
        ? visibleMessages
        : visibleMessages.sublist(visibleMessages.length - 6);

    return Material(
      color: AppTheme.background,
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.05,
              colors: [Color(0xFF142851), Color(0xFF091D18), Color(0xFF06120E)],
              stops: [0, 0.48, 1],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live with Cygnus',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Speak naturally · interrupt anytime',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface2.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        widget.languageCode.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    IconButton(
                      tooltip: 'End live interaction',
                      onPressed: widget.onEnd,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _wave,
                builder: (context, _) {
                  final phase = _wave.value * math.pi * 2;
                  final glow = 0.22 + (math.sin(phase).abs() * 0.18);
                  return Container(
                    width: 142,
                    height: 142,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF111C3D),
                      border: Border.all(
                        color: const Color(0xFF7997FF).withValues(alpha: 0.42),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF4F7DFF,
                          ).withValues(alpha: glow),
                          blurRadius: 52,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF59D7FF,
                          ).withValues(alpha: glow * 0.55),
                          blurRadius: 78,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/branding/cygnus_emblem.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                _stateLabel,
                style: TextStyle(
                  color: _stateColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: widget.speaking
                    ? _SpeakingWave(animation: _wave)
                    : _VoiceWave(
                        level: widget.listening
                            ? widget.level
                            : (widget.processing ? 0.12 : 0.04),
                      ),
              ),
              if (widget.draft.isNotEmpty &&
                  widget.draft != 'Listening…' &&
                  widget.draft != 'Understanding your voice…') ...[
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102B24).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: AppTheme.emerald.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.mic_rounded,
                          size: 16,
                          color: AppTheme.emeraldSoft,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'YOU · LIVE TRANSCRIPT',
                              style: TextStyle(
                                color: AppTheme.emeraldSoft,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.draft,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.32,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071A14).withValues(alpha: 0.84),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.72),
                    ),
                  ),
                  child: recent.isEmpty
                      ? const Center(
                          child: Text(
                            'Start speaking to Cygnus',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                          itemCount: recent.length,
                          itemBuilder: (context, reverseIndex) {
                            final message =
                                recent[recent.length - 1 - reverseIndex];
                            final user = message.role == 'user';
                            return Align(
                              alignment: user
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 340,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: user
                                      ? AppTheme.emerald.withValues(alpha: 0.13)
                                      : const Color(
                                          0xFF13223A,
                                        ).withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: user
                                        ? AppTheme.emerald.withValues(
                                            alpha: 0.22,
                                          )
                                        : const Color(
                                            0xFF526A98,
                                          ).withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _MessageMarkdown(
                                      message.text,
                                      fontSize: 12.5,
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: _CopyMessageButton(message.text),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  children: [
                    if (widget.speaking)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF24345C),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: widget.onInterrupt,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Interrupt & speak'),
                        ),
                      )
                    else if (widget.listening)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onCancelListening,
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.red,
                              ),
                              onPressed: widget.onStopListening,
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('Finish'),
                            ),
                          ),
                        ],
                      )
                    else if (!widget.processing)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onStartListening,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Speak'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: widget.onEnd,
                      icon: const Icon(Icons.call_end_rounded, size: 18),
                      label: const Text('End live interaction'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeakingWave extends StatelessWidget {
  const _SpeakingWave({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final phase = animation.value * math.pi * 2;
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(34, (index) {
          final a = math.sin((index * 0.54) + phase).abs();
          final b = math.sin((index * 0.23) - (phase * 1.35)).abs();
          final height = 5.0 + (26 * ((a * 0.68) + (b * 0.32)));
          return Expanded(
            child: Align(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.8),
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xFF7A8CFF), Color(0xFF5BE2FF)],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CygnusBar extends StatelessWidget {
  const _CygnusBar({
    required this.languageCode,
    required this.voiceReply,
    required this.voiceConversation,
    required this.voiceAvailable,
    required this.onVoiceConversation,
    required this.onSessions,
    required this.onNewChat,
    required this.onVoiceReplyChanged,
    required this.onLanguageChanged,
  });

  final String languageCode;
  final bool voiceReply;
  final bool voiceConversation;
  final bool voiceAvailable;
  final Future<void> Function() onVoiceConversation;
  final VoidCallback onSessions;
  final Future<void> Function() onNewChat;
  final ValueChanged<bool> onVoiceReplyChanged;
  final Future<void> Function(String) onLanguageChanged;

  static const _languageLabels = <String, String>{
    'en': 'EN',
    'ta': 'தமிழ்',
    'hi': 'हिं',
    'ml': 'മല',
    'kn': 'ಕಂ',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2C21), Color(0xFF0B2119)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.85)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF101D39),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFF6777FF).withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF67B8FF).withValues(alpha: 0.30),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Image.asset(
              'assets/branding/cygnus_emblem.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Cygnus',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 7),
                    _AgentBadge(),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  'Ask · Control · Plan · Diagnose',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Language',
            initialValue: languageCode,
            onSelected: onLanguageChanged,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ta', child: Text('தமிழ்')),
              PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
              PopupMenuItem(value: 'ml', child: Text('മലയാളം')),
              PopupMenuItem(value: 'kn', child: Text('ಕನ್ನಡ')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                _languageLabels[languageCode] ?? 'EN',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Tooltip(
            message: voiceConversation
                ? 'End live interaction'
                : 'Start live interaction',
            child: InkWell(
              onTap: voiceAvailable ? onVoiceConversation : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color:
                      (voiceConversation
                              ? AppTheme.red
                              : const Color(0xFF5F75FF))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (voiceConversation
                                ? AppTheme.red
                                : const Color(0xFF7193FF))
                            .withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      voiceConversation
                          ? Icons.call_end_rounded
                          : Icons.graphic_eq_rounded,
                      size: 18,
                      color: voiceConversation
                          ? AppTheme.red
                          : const Color(0xFF8FC9FF),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      voiceConversation ? 'End' : 'Live',
                      style: TextStyle(
                        color: voiceConversation
                            ? AppTheme.red
                            : const Color(0xFFAED7FF),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: voiceReply ? 'Voice replies on' : 'Voice replies off',
            onPressed: () => onVoiceReplyChanged(!voiceReply),
            icon: Icon(
              voiceReply ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              size: 21,
              color: voiceReply ? AppTheme.emeraldSoft : AppTheme.muted,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'history') onSessions();
              if (value == 'new') onNewChat();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'new',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_comment_outlined),
                  title: Text('New chat'),
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_rounded),
                  title: Text('Conversations'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentBadge extends StatelessWidget {
  const _AgentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.emerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.25)),
      ),
      child: const Text(
        'AI',
        style: TextStyle(
          color: AppTheme.emeraldSoft,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CygnusMessageView extends StatelessWidget {
  const _CygnusMessageView({
    required this.message,
    required this.pendingAction,
    required this.busy,
    required this.pendingRetryId,
    required this.onConfirm,
    required this.onCancel,
    required this.onRetry,
    required this.onDismissRetry,
    required this.onPrompt,
  });

  final CygnusMessage message;
  final PendingCygnusAction? pendingAction;
  final bool busy;
  final String? pendingRetryId;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onCancel;
  final Future<void> Function() onRetry;
  final Future<void> Function() onDismissRetry;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    Widget body;

    switch (message.kind) {
      case 'live_status':
        body = const _LiveStatusCard();
        break;
      case 'trend':
        body = _TrendCard(message: message);
        break;
      case 'leaf_result':
        body = _LeafResultCard(message: message, onPrompt: onPrompt);
        break;
      case 'confirmation':
        body = _ConfirmationCard(
          message: message,
          pendingAction: pendingAction,
          busy: busy,
          onConfirm: onConfirm,
          onCancel: onCancel,
        );
        break;
      case 'retry':
        body = _RetryInstructionCard(
          message: message,
          isPending: !busy && message.payload['retryId'] == pendingRetryId,
          onRetry: onRetry,
          onDismiss: onDismissRetry,
        );
        break;
      case 'image':
        body = _ImageMessage(message: message);
        break;
      default:
        body = _TextBubble(message: message, isUser: isUser);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isUser ? 42 : 0,
          right: isUser ? 0 : 26,
          bottom: 10,
        ),
        child: body,
      ),
    );
  }
}

class _RetryInstructionCard extends StatelessWidget {
  const _RetryInstructionCard({
    required this.message,
    required this.isPending,
    required this.onRetry,
    required this.onDismiss,
  });

  final CygnusMessage message;
  final bool isPending;
  final Future<void> Function() onRetry;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final resolved = message.payload['resolved']?.toString();
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.amber,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  resolved == null ? 'Needs attention' : 'Instruction status',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MessageMarkdown(message.text, fontSize: 13),
          const SizedBox(height: 4),
          Text(
            'Instruction: ${message.payload['instruction'] ?? ''}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          if (resolved != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                resolved,
                style: const TextStyle(color: AppTheme.muted),
              ),
            )
          else if (isPending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      child: const Text('No, leave it'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onRetry,
                      child: const Text('Yes, retry once'),
                    ),
                  ),
                ],
              ),
            ),
          if (resolved == null && !isPending)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This retry is no longer active. Submit the instruction again if needed.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.message, required this.isUser});

  final CygnusMessage message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: isUser
            ? AppTheme.emerald.withValues(alpha: 0.16)
            : AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 18),
        ),
        border: Border.all(
          color: isUser
              ? AppTheme.emerald.withValues(alpha: 0.28)
              : AppTheme.border.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MessageMarkdown(message.text, fontSize: 14),
          Align(
            alignment: Alignment.centerRight,
            child: _CopyMessageButton(message.text),
          ),
        ],
      ),
    );
  }
}

class _MessageMarkdown extends StatelessWidget {
  const _MessageMarkdown(this.data, {required this.fontSize});

  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(
      color: AppTheme.text,
      height: 1.45,
      fontSize: fontSize,
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: bodyStyle,
        h1: bodyStyle.copyWith(
          fontSize: fontSize * 1.55,
          fontWeight: FontWeight.w800,
        ),
        h2: bodyStyle.copyWith(
          fontSize: fontSize * 1.35,
          fontWeight: FontWeight.w800,
        ),
        h3: bodyStyle.copyWith(
          fontSize: fontSize * 1.15,
          fontWeight: FontWeight.w700,
        ),
        blockquote: bodyStyle.copyWith(color: AppTheme.muted),
        listBullet: bodyStyle.copyWith(color: AppTheme.emeraldSoft),
        tableBody: bodyStyle,
        code: bodyStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: AppTheme.background.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _CopyMessageButton extends StatelessWidget {
  const _CopyMessageButton(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy message',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.muted),
    );
  }
}

class _LiveStatusCard extends StatelessWidget {
  const _LiveStatusCard();

  @override
  Widget build(BuildContext context) {
    final agro = context.watch<AgroController>();
    final t = agro.telemetry;

    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(14),
      decoration: _richCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                color: AppTheme.emerald,
                size: 19,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live farm status',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _StatusDot(online: agro.deviceOnline),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                icon: Icons.thermostat_rounded,
                label: '${t.temperature.toStringAsFixed(1)}°C',
              ),
              _MetricChip(
                icon: Icons.water_drop_outlined,
                label: '${t.humidity.toStringAsFixed(0)}% humidity',
              ),
              _MetricChip(
                icon: Icons.eco_rounded,
                label: '${t.soil.toStringAsFixed(0)}% soil',
              ),
              _MetricChip(
                icon: Icons.waves_rounded,
                label: '${t.waterLevel.toStringAsFixed(0)}% water',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MotorDot(label: 'M1', on: agro.controls.actual2),
              const SizedBox(width: 7),
              _MotorDot(label: 'M2', on: agro.controls.actual3),
              const SizedBox(width: 7),
              _MotorDot(label: 'M3', on: agro.controls.actual4),
              const SizedBox(width: 7),
              _MotorDot(label: 'AUTO', on: t.led1),
              const Spacer(),
              Text(
                agro.deviceOnline ? 'Updating live' : 'Waiting for device',
                style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.message});

  final CygnusMessage message;

  @override
  Widget build(BuildContext context) {
    final payload = message.payload;
    final rawPoints = payload['points'];
    final points = <Map<String, dynamic>>[];
    if (rawPoints is List) {
      for (final item in rawPoints) {
        if (item is Map) points.add(Map<String, dynamic>.from(item));
      }
    }
    final metric = payload['metric']?.toString() ?? 'temperature';
    final minutes = (payload['minutes'] as num?)?.toInt() ?? 10;
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final value = points[i]['value'];
      if (value is num) spots.add(FlSpot(i.toDouble(), value.toDouble()));
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(14),
      decoration: _richCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_metricIcon(metric), color: _metricColor(metric), size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_metricName(metric)} · last $minutes min',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 145,
            child: spots.length < 2
                ? const Center(
                    child: Text(
                      'Not enough recent readings yet.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: math.max(1, spots.length - 1).toDouble(),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: AppTheme.border.withValues(alpha: 0.45),
                          strokeWidth: 0.7,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          barWidth: 2.4,
                          color: _metricColor(metric),
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _metricColor(metric).withValues(alpha: 0.18),
                                _metricColor(metric).withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 220),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LeafResultCard extends StatelessWidget {
  const _LeafResultCard({required this.message, required this.onPrompt});

  final CygnusMessage message;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final p = message.payload;
    final crop = p['crop']?.toString() ?? 'Plant';
    final condition = p['condition']?.toString() ?? 'Result';
    final confidence = (p['confidence'] as num?)?.toDouble() ?? 0;
    final treatment = _toStrings(p['treatment']);
    final prevention = _toStrings(p['prevention']);

    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(15),
      decoration: _richCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco_rounded, color: AppTheme.emerald),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crop,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      condition,
                      style: const TextStyle(
                        color: AppTheme.emeraldSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${(confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (treatment.isNotEmpty) ...[
            const SizedBox(height: 13),
            const Text(
              'Care',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 5),
            for (final item in treatment.take(3)) _AdviceLine(text: item),
          ],
          if (prevention.isNotEmpty) ...[
            const SizedBox(height: 9),
            TextButton.icon(
              onPressed: () => onPrompt(
                'Tell me the prevention steps for this leaf result.',
              ),
              icon: const Icon(Icons.shield_outlined, size: 17),
              label: const Text('Prevention tips'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.message,
    required this.pendingAction,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final CygnusMessage message;
  final PendingCygnusAction? pendingAction;
  final bool busy;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final pendingId = message.payload['pendingId']?.toString();
    final active = pendingAction != null && pendingAction!.id == pendingId;
    final destructive = message.payload['destructive'] == true;

    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (destructive ? AppTheme.red : AppTheme.emerald).withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                destructive
                    ? Icons.delete_outline_rounded
                    : Icons.event_available_rounded,
                color: destructive ? AppTheme.red : AppTheme.emerald,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message.payload['title']?.toString() ?? 'Confirm action',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            message.payload['details']?.toString() ?? message.text,
            style: const TextStyle(color: AppTheme.muted, height: 1.45),
          ),
          const SizedBox(height: 13),
          if (active)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FilledButton(
                    style: destructive
                        ? FilledButton.styleFrom(backgroundColor: AppTheme.red)
                        : null,
                    onPressed: busy ? null : onConfirm,
                    child: Text(destructive ? 'Delete' : 'Confirm'),
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppTheme.muted,
                  size: 17,
                ),
                SizedBox(width: 6),
                Text(
                  'Completed',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ImageMessage extends StatelessWidget {
  const _ImageMessage({required this.message});

  final CygnusMessage message;

  @override
  Widget build(BuildContext context) {
    final path = message.payload['path']?.toString();
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return _TextBubble(message: message, isUser: true);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Image.file(File(path), width: 220, height: 180, fit: BoxFit.cover),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Checking leaf',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 70),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text(
              'Cygnus is working…',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceStrip extends StatelessWidget {
  const _VoiceStrip({
    required this.text,
    required this.level,
    required this.processing,
    required this.onStop,
    required this.onCancel,
  });

  final String text;
  final double level;
  final bool processing;
  final Future<void> Function() onStop;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 7, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF15254B).withValues(alpha: 0.96),
            const Color(0xFF0C2A23).withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6D7DFF).withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF536DFF).withValues(alpha: 0.10),
            blurRadius: 22,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF101C3D),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF58C7FF).withValues(alpha: 0.28),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Image.asset(
              'assets/branding/cygnus_emblem.png',
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  processing
                      ? 'Understanding your voice…'
                      : 'Listening · speak naturally',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                if (processing)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                  )
                else
                  _VoiceWave(level: normalized),
                if (text.isNotEmpty &&
                    text != 'Listening…' &&
                    text != 'Understanding your voice…') ...[
                  const SizedBox(height: 6),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.emeraldSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!processing)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Finish and send',
              onPressed: onStop,
              icon: const Icon(
                Icons.stop_circle_rounded,
                color: AppTheme.red,
                size: 26,
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Cancel voice input',
            onPressed: onCancel,
            icon: const Icon(
              Icons.close_rounded,
              color: AppTheme.muted,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionQueueOverlay extends StatelessWidget {
  const _InstructionQueueOverlay({
    required this.active,
    required this.waiting,
    required this.completed,
    required this.skipped,
    required this.total,
    required this.progress,
    required this.running,
    required this.waitingForConfirmation,
    required this.waitingForDecision,
    required this.waitingForClarification,
    required this.clarificationQuestion,
    required this.restoring,
    required this.failedInstruction,
  });

  final String? active;
  final List<String> waiting;
  final int completed;
  final int skipped;
  final int total;
  final double progress;
  final bool running;
  final bool waitingForConfirmation;
  final bool waitingForDecision;
  final bool waitingForClarification;
  final String? clarificationQuestion;
  final bool restoring;
  final String? failedInstruction;

  @override
  Widget build(BuildContext context) {
    final title = waitingForClarification
        ? 'Need a schedule detail'
        : waitingForDecision
        ? 'Action needs your choice'
        : waitingForConfirmation
        ? 'Waiting for schedule confirmation'
        : restoring
        ? 'Restoring saved instructions'
        : running
        ? 'Processing instruction queue'
        : 'Instructions queued';
    final current = waitingForClarification
        ? clarificationQuestion ?? active
        : waitingForDecision
        ? failedInstruction
        : active ?? (waiting.isNotEmpty ? waiting.first : null);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
          decoration: BoxDecoration(
            color: const Color(0xF20B1E17),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: waitingForDecision
                  ? AppTheme.amber.withValues(alpha: 0.52)
                  : AppTheme.emerald.withValues(alpha: 0.35),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    waitingForDecision || waitingForClarification
                        ? Icons.warning_amber_rounded
                        : waitingForConfirmation
                        ? Icons.event_available_rounded
                        : Icons.queue_play_next_rounded,
                    size: 18,
                    color: waitingForDecision || waitingForClarification
                        ? AppTheme.amber
                        : AppTheme.emeraldSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '$completed done · $skipped skipped · ${waiting.length} waiting',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              if (current != null) ...[
                const SizedBox(height: 7),
                Text(
                  current,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.text, fontSize: 11.5),
                ),
              ],
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: total == 0 ? null : progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: AppTheme.border,
                color: waitingForDecision || waitingForClarification
                    ? AppTheme.amber
                    : AppTheme.emerald,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(24, (index) {
          final phase = math.sin((index + 1) * 0.83).abs();
          final emphasis = 0.18 + (level * 0.82);
          final height = 4.0 + (22.0 * emphasis * (0.35 + phase * 0.65));
          return Expanded(
            child: Align(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                height: height.clamp(4.0, 26.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xFF49E7B3), Color(0xFF67A7FF)],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.queuedInstructionCount,
    required this.listening,
    required this.voiceProcessing,
    required this.voiceAvailable,
    required this.onAttach,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final int queuedInstructionCount;
  final bool listening;
  final bool voiceProcessing;
  final bool voiceAvailable;
  final VoidCallback onAttach;
  final Future<void> Function() onSend;
  final Future<void> Function() onMic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF081A13),
          border: Border(top: BorderSide(color: AppTheme.border, width: 0.7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton.filledTonal(
              tooltip: 'Add leaf photo',
              onPressed: busy ? null : onAttach,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 48,
                  maxHeight: 130,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: queuedInstructionCount > 0
                        ? 'Queue instruction · $queuedInstructionCount waiting'
                        : (busy ? 'Add instruction to queue…' : 'Ask Cygnus…'),
                    hintStyle: TextStyle(color: AppTheme.muted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            IconButton.filledTonal(
              tooltip: listening ? 'Stop listening' : 'Talk to Cygnus',
              onPressed: busy || voiceProcessing || !voiceAvailable
                  ? null
                  : onMic,
              icon: Icon(
                voiceProcessing
                    ? Icons.more_horiz_rounded
                    : (listening ? Icons.stop_rounded : Icons.mic_rounded),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.emeraldSoft),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MotorDot extends StatelessWidget {
  const _MotorDot({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (on ? AppTheme.emerald : AppTheme.surface2).withValues(
          alpha: on ? 0.12 : 1,
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: on
              ? AppTheme.emerald.withValues(alpha: 0.28)
              : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AppTheme.emerald : AppTheme.muted,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$label ${on ? 'ON' : 'OFF'}',
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (online ? AppTheme.emerald : AppTheme.red).withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? AppTheme.emerald : AppTheme.red,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            online ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: online ? AppTheme.emeraldSoft : AppTheme.red,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdviceLine extends StatelessWidget {
  const _AdviceLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: AppTheme.emerald),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.muted,
                height: 1.35,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      tileColor: AppTheme.surface2,
      leading: Icon(icon, color: AppTheme.emerald),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppTheme.muted, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
    );
  }
}

BoxDecoration _richCardDecoration() => BoxDecoration(
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F281E), Color(0xFF0B1E17)],
  ),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: AppTheme.border.withValues(alpha: 0.9)),
);

List<String> _toStrings(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .toList(growable: false);
}

Color _metricColor(String metric) => switch (metric) {
  'humidity' => AppTheme.cyan,
  'soil' => AppTheme.emerald,
  'water' || 'waterlevel' || 'water_level' => const Color(0xFF5EB6FF),
  _ => const Color(0xFFFF8C92),
};

IconData _metricIcon(String metric) => switch (metric) {
  'humidity' => Icons.water_drop_outlined,
  'soil' => Icons.eco_rounded,
  'water' || 'waterlevel' || 'water_level' => Icons.waves_rounded,
  _ => Icons.thermostat_rounded,
};

String _metricName(String metric) => switch (metric) {
  'humidity' => 'Humidity',
  'soil' => 'Soil moisture',
  'water' || 'waterlevel' || 'water_level' => 'Water level',
  _ => 'Temperature',
};

String _relativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays} days ago';
}
