import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

/// Safe, stable diagnostics. Never display or log the original exception text:
/// service errors can include credentials, request data, or generated content.
class CygnusDiagnostic implements Exception {
  const CygnusDiagnostic(this.code, this.message);

  final String code;
  final String message;

  static CygnusDiagnostic fromError(Object error) {
    if (error is CygnusDiagnostic) return error;
    final details = error.toString().toLowerCase();
    if (details.contains("role 'function' is not supported") ||
        details.contains('role "function" is not supported')) {
      return const CygnusDiagnostic(
        'tool_protocol_error',
        'The AI service rejected this app’s tool-response format. Install '
            'the updated Cygnus build; changing App Check tokens will not '
            'fix this format error.',
      );
    }
    final appCheck =
        (error is FirebaseException && error.plugin == 'firebase_app_check') ||
        RegExp(r'app[ _-]?check').hasMatch(details);
    if (appCheck) {
      if (details.contains('too many attempts') ||
          details.contains('throttl') ||
          details.contains('too many requests') ||
          details.contains('429')) {
        return const CygnusDiagnostic(
          'app_check_throttled',
          'App verification is temporarily throttled. For a test APK, register '
              'this device’s App Check debug token first. Allow the server '
              'backoff period to pass before reopening the app; repeated '
              'attempts will not clear the throttle.',
        );
      }
      return const CygnusDiagnostic(
        'app_check_failed',
        'App Check could not verify this app. For a debug test APK, confirm '
            'this device’s debug token is registered for the correct Firebase '
            'app, then reopen it. Production builds require Play Integrity.',
      );
    }
    if (error is TimeoutException) {
      return const CygnusDiagnostic(
        'timeout',
        'Cygnus did not receive a response in time. Check your connection '
            'before trying again.',
      );
    }
    if (error is QuotaExceeded ||
        details.contains('resource_exhausted') ||
        details.contains('quota') ||
        details.contains('429')) {
      return const CygnusDiagnostic(
        'quota_exceeded',
        'Cygnus has reached an AI usage limit. Wait for the quota to recover '
            'or check the project’s quota and billing settings.',
      );
    }
    if (error is ServiceApiNotEnabled ||
        details.contains('service_disabled') ||
        details.contains('api has not been used') ||
        details.contains('api is not enabled')) {
      return const CygnusDiagnostic(
        'api_not_enabled',
        'Cygnus needs the required Firebase AI Logic API enabled for this project.',
      );
    }
    if (error is InvalidApiKey ||
        details.contains('api_key_invalid') ||
        details.contains('api key not valid') ||
        details.contains('invalid api key')) {
      return const CygnusDiagnostic(
        'invalid_api_key',
        'Cygnus could not verify the Firebase API configuration. Check that '
            'the app configuration belongs to the correct Firebase project.',
      );
    }
    if (details.contains('permission_denied') ||
        details.contains('permission-denied') ||
        details.contains('403') ||
        details.contains('unauthenticated') ||
        details.contains('401')) {
      return const CygnusDiagnostic(
        'permission_denied',
        'Firebase denied this AI request. Check the project, API access and '
            'key restrictions. This error alone does not identify App Check '
            'as the cause.',
      );
    }
    if (details.contains('model') &&
        (details.contains('not found') ||
            details.contains('not_found') ||
            details.contains('not supported') ||
            details.contains('404'))) {
      return const CygnusDiagnostic(
        'model_unavailable',
        'The configured Cygnus model is unavailable for this project. '
            'Check its supported model name and project access.',
      );
    }
    if (details.contains('socketexception') ||
        details.contains('clientexception') ||
        details.contains('network') ||
        details.contains('connection') ||
        details.contains('unavailable') ||
        details.contains('503')) {
      return const CygnusDiagnostic(
        'network_or_service',
        'Cygnus could not reach the AI service. Check your connection and '
            'try again when the service is available.',
      );
    }
    return const CygnusDiagnostic(
      'request_failed',
      'Cygnus couldn’t complete that request. The diagnostic log contains '
          'a safe error category for troubleshooting.',
    );
  }

  @override
  String toString() => code;
}
