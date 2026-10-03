import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:agro_connect/cygnus/cygnus_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('CygnusMessage round trips through JSON', () {
    final message = CygnusMessage(
      id: 'm1',
      role: 'assistant',
      text: 'Motor 2 started.',
      kind: 'text',
      payload: const <String, dynamic>{'motor': 2, 'state': true},
      createdAt: DateTime.fromMillisecondsSinceEpoch(123456789),
    );

    final decoded = CygnusMessage.decode(message.encode());
    expect(decoded.id, 'm1');
    expect(decoded.role, 'assistant');
    expect(decoded.text, 'Motor 2 started.');
    expect(decoded.payload['motor'], 2);
    expect(decoded.payload['state'], true);
    expect(decoded.createdAt.millisecondsSinceEpoch, 123456789);
  });

  test('Cygnus session summary reads persisted metadata', () {
    final summary = CygnusSessionSummary.fromMap('chat_1', <String, dynamic>{
      'title': 'Morning plan',
      'languageCode': 'ta',
      'updatedAt': 1000,
    });

    expect(summary.id, 'chat_1');
    expect(summary.title, 'Morning plan');
    expect(summary.languageCode, 'ta');
    expect(summary.updatedAt.millisecondsSinceEpoch, 1000);
  });

  test('retry decisions recognize leave and skip phrases', () {
    for (final phrase in [
      'leave it',
      'No, leave it',
      'skip this',
      'no need, skip the first one',
      'வேண்டாம்',
    ]) {
      expect(parseCygnusDecision(phrase), CygnusDecision.skip, reason: phrase);
    }
    expect(parseCygnusDecision('yes, retry'), CygnusDecision.approve);
    expect(parseCygnusDecision('leave the motor on'), CygnusDecision.none);
    expect(
      parseCygnusDecision('motor 2 schedule tomorrow'),
      CygnusDecision.none,
    );
  });

  test('separate instruction lines are split and empty lines are ignored', () {
    expect(
      splitCygnusInstructions(
        'Schedule motor 1\n\nSchedule motor 2; check status',
      ),
      ['Schedule motor 1', 'Schedule motor 2', 'check status'],
    );
  });

  test('schedule instructions without a start date need clarification', () {
    expect(
      needsCygnusScheduleDateClarification(
        'Schedule motor 1 at 6 PM for 30 minutes',
      ),
      isTrue,
    );
    expect(
      needsCygnusScheduleDateClarification('Schedule motor 1 tomorrow at 6 PM'),
      isFalse,
    );
    expect(
      needsCygnusScheduleDateClarification(
        'Schedule motor 1 at 6 PM starting 2026-10-10',
      ),
      isFalse,
    );
    expect(
      needsCygnusScheduleDateClarification(
        'Schedule motor 1 at 6 PM next week',
      ),
      isTrue,
    );
    expect(
      needsCygnusScheduleDateClarification(
        'மோட்டார் அட்டவணை நாளை மாலை 6 மணிக்கு',
      ),
      isFalse,
    );
    expect(
      needsCygnusScheduleDateClarification('Show the schedule for motor 1'),
      isFalse,
    );
    expect(
      needsCygnusScheduleDateClarification('Update motor 1 schedule time to 6'),
      isFalse,
    );
  });

  test('queued instruction round trips state before restart recovery', () {
    const instruction = CygnusQueuedInstruction(
      id: 'instruction-1',
      text: 'Schedule motor 2',
      fromVoice: true,
      started: true,
      retryCount: 1,
      awaitingClarification: true,
      clarificationQuestion: 'Which date should I use?',
      clarificationAnswers: ['tomorrow'],
    );

    final restored = CygnusQueuedInstruction.fromMap(instruction.toMap());

    expect(restored.id, instruction.id);
    expect(restored.text, instruction.text);
    expect(restored.fromVoice, isTrue);
    expect(restored.started, isTrue);
    expect(restored.retryCount, 1);
    expect(restored.awaitingClarification, isTrue);
    expect(restored.clarificationQuestion, 'Which date should I use?');
    expect(restored.clarificationAnswers, ['tomorrow']);
    final resumed = restored.copyWith(
      awaitingClarification: false,
      clearClarificationQuestion: true,
    );
    expect(resumed.awaitingClarification, isFalse);
    expect(resumed.clarificationQuestion, isNull);
  });

  test('skipping one instruction preserves later FIFO instructions', () {
    const instructions = [
      CygnusQueuedInstruction(
        id: 'first',
        text: 'Retry or skip',
        fromVoice: false,
      ),
      CygnusQueuedInstruction(
        id: 'second',
        text: 'Motor 1 schedule',
        fromVoice: false,
      ),
      CygnusQueuedInstruction(
        id: 'third',
        text: 'Motor 2 schedule',
        fromVoice: false,
      ),
    ];

    final remaining = withoutCygnusInstruction(instructions, 'first');

    expect(remaining.map((instruction) => instruction.id), ['second', 'third']);
    expect(remaining.map((instruction) => instruction.text), [
      'Motor 1 schedule',
      'Motor 2 schedule',
    ]);
  });

  test('session store keeps pending instructions in FIFO order', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CygnusSessionStore();
    const queue = [
      CygnusQueuedInstruction(
        id: 'first',
        text: 'Create motor 1 schedule',
        fromVoice: false,
      ),
      CygnusQueuedInstruction(
        id: 'second',
        text: 'Create motor 2 schedule',
        fromVoice: true,
        started: true,
        awaitingClarification: true,
        clarificationQuestion: 'Which day should I use?',
        clarificationAnswers: ['Friday'],
      ),
    ];

    await store.saveInstructionQueue('chat_1', queue);
    final restored = await store.loadInstructionQueue('chat_1');

    expect(restored.map((item) => item.id), ['first', 'second']);
    expect(restored.map((item) => item.text), [
      'Create motor 1 schedule',
      'Create motor 2 schedule',
    ]);
    expect(restored.last.awaitingClarification, isTrue);
    expect(restored.last.clarificationQuestion, 'Which day should I use?');
    expect(restored.last.clarificationAnswers, ['Friday']);

    await store.saveInstructionQueue('chat_1', const []);
    expect(await store.loadInstructionQueue('chat_1'), isEmpty);
  });
}
