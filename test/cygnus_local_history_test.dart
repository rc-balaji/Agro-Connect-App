import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agro_connect/cygnus/cygnus_session_store.dart';
import 'package:agro_connect/cygnus/cygnus_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'local history survives a new store with no Firebase initialization',
    () async {
      final store = CygnusSessionStore();
      await store.initialize();
      final id = await store.createSession(languageCode: 'ta');
      await store.updateSession(sessionId: id, title: 'My farm');
      await Future.wait(
        List.generate(
          4,
          (i) => store.saveMessage(
            id,
            CygnusMessage(
              id: 'm$i',
              role: 'user',
              text: 'message $i',
              createdAt: DateTime.now(),
            ),
          ),
        ),
      );
      final reopened = CygnusSessionStore();
      await reopened.initialize();
      expect(reopened.cloudEnabled, false);
      expect((await reopened.listSessions()).single.title, 'My farm');
      expect((await reopened.loadMessages(id)).length, 4);
      await reopened.deleteSession(id);
      expect(await reopened.listSessions(), isEmpty);
      expect(await reopened.loadMessages(id), isEmpty);
    },
  );
}
