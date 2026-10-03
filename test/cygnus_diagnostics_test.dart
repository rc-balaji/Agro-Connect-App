import 'dart:async';

import 'package:agro_connect/cygnus/cygnus_diagnostics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backend role rejection is an app protocol error, not App Check', () {
    final diagnostic = CygnusDiagnostic.fromError(
      Exception(
        "Role 'function' is not supported. Valid roles are SYSTEM, USER, MODEL.",
      ),
    );
    expect(diagnostic.code, 'tool_protocol_error');
  });

  test('actual App Check throttling is distinct from AI quota exhaustion', () {
    final diagnostic = CygnusDiagnostic.fromError(
      FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: 'Too many attempts.',
      ),
    );
    expect(diagnostic.code, 'app_check_throttled');
    expect(diagnostic.message, contains('backoff'));
    expect(
      CygnusDiagnostic.fromError(Exception('429 RESOURCE_EXHAUSTED')).code,
      'quota_exceeded',
    );
  });

  test('generic permissions do not diagnose App Check without evidence', () {
    final generic = CygnusDiagnostic.fromError(
      Exception('403 PERMISSION_DENIED: The caller does not have permission.'),
    );
    final appCheck = CygnusDiagnostic.fromError(
      Exception('403 PERMISSION_DENIED: Firebase App Check token is invalid.'),
    );
    expect(generic.code, 'permission_denied');
    expect(appCheck.code, 'app_check_failed');
  });

  test('diagnostics never expose service error payloads or secrets', () {
    const secret = 'private-debug-secret-and-request-text';
    for (final raw in <String>[
      'AppCheck failed: $secret',
      '403 PERMISSION_DENIED $secret',
      'unexpected response: $secret',
    ]) {
      final diagnostic = CygnusDiagnostic.fromError(Exception(raw));
      expect(diagnostic.message, isNot(contains(secret)));
      expect(diagnostic.toString(), isNot(contains(secret)));
    }
  });

  test(
    'timeouts and unavailable models have actionable separate categories',
    () {
      expect(
        CygnusDiagnostic.fromError(TimeoutException('private request')).code,
        'timeout',
      );
      expect(
        CygnusDiagnostic.fromError(Exception('404 model not found')).code,
        'model_unavailable',
      );
    },
  );
}
