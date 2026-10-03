import 'package:agro_connect/controllers/cygnus_controller.dart';
import 'package:agro_connect/cygnus/cygnus_voice_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoice extends CygnusVoiceService {
  int starts = 0;
  int cancels = 0;
  ValueChanged<String?>? ended;
  @override
  bool get available => true;
  @override
  bool get listening => false; // Simulate Android's asynchronous start status.
  @override
  Future<void> initialize() async {}
  @override
  Future<void> stopSpeaking() async {}
  @override
  Future<void> cancelListening() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> startListening({
    required String languageCode,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    ValueChanged<bool>? onListening,
    ValueChanged<String?>? onEnded,
  }) async {
    starts++;
    ended = onEnded;
    onListening?.call(true);
  }
}

void main() {
  testWidgets(
    'asynchronous listening does not immediately end the conversation',
    (tester) async {
      final voice = FakeVoice();
      final controller = CygnusController(voiceService: voice);
      await controller.startVoiceConversation();
      expect(controller.voiceConversation, true);
      expect(controller.listening, true);
      voice.ended!(null);
      await tester.pump(const Duration(milliseconds: 701));
      expect(voice.starts, 2);
      await controller.stopVoiceConversation();
      await tester.pump(const Duration(seconds: 2));
      expect(voice.starts, 2);
      expect(controller.voiceConversation, false);
      controller.dispose();
    },
  );
  testWidgets(
    'silence retries are bounded and real errors stop with guidance',
    (tester) async {
      final voice = FakeVoice();
      final controller = CygnusController(voiceService: voice);
      await controller.startVoiceConversation();
      for (var i = 0; i < 3; i++) {
        voice.ended!(null);
        await tester.pump(const Duration(milliseconds: 701));
      }
      expect(voice.starts, 3);
      expect(controller.voiceConversation, false);
      expect(controller.voiceNotice, contains('No speech detected'));
      await controller.startVoiceConversation();
      voice.ended!('Microphone unavailable.');
      await tester.pump(const Duration(seconds: 2));
      expect(controller.voiceNotice, 'Microphone unavailable.');
      expect(controller.voiceConversation, false);
      expect(voice.starts, 4);
      controller.dispose();
    },
  );
}
