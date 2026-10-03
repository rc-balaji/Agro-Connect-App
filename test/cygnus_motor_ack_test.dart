import 'package:agro_connect/controllers/agro_controller.dart';
import 'package:agro_connect/controllers/cygnus_controller.dart';
import 'package:agro_connect/controllers/plan_controller.dart';
import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:agro_connect/cygnus/cygnus_session_store.dart';
import 'package:agro_connect/models/control_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'cygnus_voice_flow_test.dart' show FakeVoice;

class MemoryStore extends CygnusSessionStore {
  @override
  Future<String> createSession({
    required String languageCode,
    String title = 'New chat',
  }) async => 'test';
  @override
  Future<void> saveMessage(String id, CygnusMessage message) async {}
  @override
  Future<void> updateSession({
    required String sessionId,
    String? title,
    String? languageCode,
  }) async {}
  @override
  Future<List<CygnusSessionSummary>> listSessions() async => [];
}

class FakeFarm extends AgroController {
  FakeFarm(this.correctAck);
  final bool correctAck;
  @override
  bool get deviceOnline => true;
  @override
  ControlState get controls => ControlState(
    actual3: true,
    lastCommandId: correctAck ? 'new-command' : 'old-command',
  );
  @override
  Future<String?> setMotor(int motor, bool value) async => 'new-command';
}

void main() {
  for (final correct in [true, false]) {
    testWidgets('motor acknowledgement must match current command: $correct', (
      tester,
    ) async {
      final farm = FakeFarm(correct);
      final plan = PlanController();
      final controller = CygnusController(
        sessionStore: MemoryStore(),
        voiceService: FakeVoice(),
      );
      controller.setVoiceReply(false);
      controller.attach(farm, plan);
      // The controller's device deadline is wall-clock based.
      await tester.runAsync(() => controller.sendText('motor 2 on'));
      expect(
        controller.messages.last.text,
        correct
            ? 'Motor 2 started.'
            : 'Command sent, but the device did not confirm the new state in time.',
      );
      controller.dispose();
      farm.dispose();
      plan.dispose();
    });
  }
}
