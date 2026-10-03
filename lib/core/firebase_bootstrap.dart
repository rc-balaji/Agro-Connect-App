import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static const bool _forceDebugAppCheck = bool.fromEnvironment(
    'AGRO_APP_CHECK_DEBUG',
    defaultValue: false,
  );

  static bool _initialized = false;
  static String? _warning;

  static bool get initialized => _initialized;
  static String? get warning => _warning;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (error, stack) {
      _warning = 'Firebase could not initialize.';
      debugPrint('Firebase initialization failed: $error\n$stack');
      return;
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: (kReleaseMode && !_forceDebugAppCheck)
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    } catch (error, stack) {
      // Do not block the core farm app if App Check is not configured yet.
      // Firebase Console enforcement should only be enabled after valid traffic
      // is visible for the production signing certificate.
      _warning = 'App protection is not fully configured yet.';
      debugPrint('Firebase App Check activation failed: $error\n$stack');
    }
  }
}
