import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'AGRO CONNECT currently ships Firebase configuration for Android only.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase options are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAwp_pMgZQAl4VJnxKMDHRBAHAO62H-9xs',
    appId: '1:511349752641:android:cb380e3a64c8f0ccc517c0',
    messagingSenderId: '511349752641',
    projectId: 'agro-connect-29b39',
    databaseURL:
        'https://agro-connect-29b39-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'agro-connect-29b39.firebasestorage.app',
  );
}
