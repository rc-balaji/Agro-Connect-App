import 'dart:async';
import 'package:agro_connect/controllers/cygnus_controller.dart';
import 'package:agro_connect/core/firebase_bootstrap.dart';
import 'package:agro_connect/cygnus/cygnus_live_service.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'cygnus_voice_flow_test.dart' show FakeVoice;

class FakeLive extends CygnusLiveService {
  int starts = 0;
  int stops = 0;
  void Function(String)? status;
  void Function(Object)? error;
  Future<Map<String, Object?>> Function(String, Map<String, Object?>)? tool;
  final connected = Completer<void>();
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> start({
    required String instruction,
    required List<Tool> tools,
    required Future<Map<String, Object?>> Function(String, Map<String, Object?>)
    onTool,
    required void Function(String) onStatus,
    required void Function(String, bool) onTranscript,
    required void Function(Object) onError,
  }) async {
    starts++;
    status = onStatus;
    error = onError;
    tool = onTool;
    onStatus('Connecting Live audio…');
    await connected.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('numeric labels are not valid debug token secrets', () {
    expect(FirebaseBootstrap.isValidDebugToken('9080778096'), false);
    expect(
      FirebaseBootstrap.isValidDebugToken(
        '11111111-1111-4111-8111-111111111111',
      ),
      true,
    );
    expect(
      FirebaseBootstrap.isValidDebugToken(
        '11111111-1111-1111-8111-111111111111',
      ),
      false,
    );
  });
  test(
    'Stop during Live connection ignores late events and blocks duplicate starts',
    () async {
      final live = FakeLive();
      final controller = CygnusController(
        voiceService: FakeVoice(),
        liveService: live,
      );
      final starting = controller.startLiveConversation();
      await Future<void>.delayed(Duration.zero);
      expect(controller.liveActive, true);
      await controller.startLiveConversation();
      expect(live.starts, 1);
      final blocked = await live.tool!('set_motor', {
        'motor': 1,
        'state': true,
      });
      expect(blocked['ok'], false);
      await controller.stopVoiceConversation();
      live.status!('Late speaking event');
      live.error!(StateError('Late error'));
      live.connected.complete();
      await starting;
      expect(controller.liveActive, false);
      expect(controller.status, 'Ready');
      controller.dispose();
    },
  );
}
