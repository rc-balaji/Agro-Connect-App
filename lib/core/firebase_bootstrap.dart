import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static const _debugToken = String.fromEnvironment(
    'AGRO_APP_CHECK_DEBUG_TOKEN',
  );

  static bool isValidDebugToken(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  static const bool _forceDebugAppCheck = bool.fromEnvironment(
    'AGRO_APP_CHECK_DEBUG',
    defaultValue: false,
  );

  static bool _initialized = false;
  static String? _warning;

  static bool get initialized => _initialized;
  static String? get warning => _warning;
  static bool get usesDebugAppCheck => kDebugMode || _forceDebugAppCheck;
  static String get appCheckProvider =>
      usesDebugAppCheck ? 'debug' : 'play_integrity';

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (error) {
      _warning = 'Firebase could not initialize.';
      debugPrint(
        '[AppCheck] stage=firebase_initialize status=failed '
        'type=${error.runtimeType}',
      );
      return;
    }

    try {
      if (usesDebugAppCheck &&
          _debugToken.isNotEmpty &&
          !isValidDebugToken(_debugToken)) {
        throw const FormatException('App Check debug token must be UUID v4.');
      }
      debugPrint(
        '[AppCheck] provider=$appCheckProvider '
        'project=${Firebase.app().options.projectId}',
      );
      await FirebaseAppCheck.instance.activate(
        providerAndroid: usesDebugAppCheck
            ? AndroidDebugProvider(
                debugToken: _debugToken.isEmpty ? null : _debugToken,
              )
            : const AndroidPlayIntegrityProvider(),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      // Activation installs the provider; only a successful request verifies
      // token exchange. Let the SDK fetch/cache tokens for actual requests.
      debugPrint(
        '[AppCheck] provider=$appCheckProvider status=activated '
        'verification=pending_request',
      );
    } catch (error) {
      // Do not block the core farm app if App Check is not configured yet.
      // Firebase Console enforcement should only be enabled after valid traffic
      // is visible for the production signing certificate.
      _warning = 'App protection is not fully configured yet.';
      debugPrint(
        '[AppCheck] provider=$appCheckProvider '
        'stage=activate status=failed type=${error.runtimeType}',
      );
    }
  }
}
