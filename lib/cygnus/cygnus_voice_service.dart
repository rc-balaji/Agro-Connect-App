import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class CygnusVoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  Future<void>? _initialization;
  bool _available = false;
  bool _turnOpen = false;
  int _generation = 0;
  Timer? _endTimer;
  ValueChanged<bool>? _onListening;
  ValueChanged<String?>? _onEnded;
  bool get available => _available;
  bool get listening => _speech.isListening;
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      _available = await _speech.initialize(
        onError: (error) {
          if (!_turnOpen) return;
          final code = error.errorMsg;
          debugPrint('[CygnusVoice] recognition_error=$code');
          if (code == 'error_no_match' || code == 'error_speech_timeout') {
            _finish(null);
          } else {
            _finish(
              code.contains('permission') || code.contains('audio')
                  ? 'Microphone unavailable. Check microphone permission and try again.'
                  : 'Speech recognition stopped. Check your connection and selected language, then tap the mic.',
            );
          }
        },
        onStatus: (status) {
          if (!_turnOpen) return;
          if (status == 'listening') {
            _endTimer?.cancel();
            _onListening?.call(true);
          } else if (status == 'done' || status == 'notListening') {
            // Final words can arrive after Android's done event.
            _endTimer?.cancel();
            _endTimer = Timer(
              const Duration(milliseconds: 800),
              () => _finish(null),
            );
          }
        },
        options: <SpeechConfigOption>[SpeechToText.androidNoBluetooth],
      );
    } catch (_) {
      _available = false;
    }
    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1);
      await _tts.setVolume(1);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      debugPrint('[CygnusVoice] tts_initialize_failed');
    }
  }

  void _finish(String? message) {
    if (!_turnOpen) return;
    _turnOpen = false;
    _endTimer?.cancel();
    _onListening?.call(false);
    _onEnded?.call(message);
  }

  Future<void> startListening({
    required String languageCode,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    ValueChanged<bool>? onListening,
    ValueChanged<String?>? onEnded,
  }) async {
    final requestedGeneration = ++_generation;
    await initialize();
    if (requestedGeneration != _generation) return;
    _turnOpen = false;
    _endTimer?.cancel();
    try {
      await _speech.cancel();
    } catch (_) {}
    if (requestedGeneration != _generation) return;
    _onListening = onListening;
    _onEnded = onEnded;
    if (!_available) {
      onEnded?.call(
        'Speech recognition is unavailable. Check microphone permission and the phone’s speech service.',
      );
      return;
    }
    final generation = requestedGeneration;
    _turnOpen = true;
    final locale = await _bestLocale(languageCode);
    if (!_turnOpen || generation != _generation) return;
    if (locale == null) {
      _finish(
        'Selected speech language is unavailable on this phone. Install its speech language or use Live audio.',
      );
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) {
          if (!_turnOpen || generation != _generation) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          if (result.finalResult) {
            _turnOpen = false;
            _endTimer?.cancel();
            _onListening?.call(false);
            onFinal(words);
          } else {
            onPartial(words);
          }
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 5),
          localeId: locale,
        ),
      );
    } catch (_) {
      _finish('Could not start listening. Tap the mic to try again.');
    }
  }

  Future<void> stopListening() => cancelListening();
  Future<void> cancelListening() async {
    ++_generation;
    _turnOpen = false;
    _endTimer?.cancel();
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  Future<void> speak(String text, String languageCode) async {
    if (text.trim().isEmpty) return;
    await initialize();
    await _tts.stop();
    final locale = switch (languageCode) {
      'ta' => 'ta-IN',
      'hi' => 'hi-IN',
      'ml' => 'ml-IN',
      'kn' => 'kn-IN',
      _ => 'en-IN',
    };
    if (await _tts.isLanguageAvailable(locale) != true) {
      throw StateError('Selected text-to-speech language is not installed.');
    }
    await _tts.setLanguage(locale);
    final result = await _tts.speak(text).timeout(const Duration(seconds: 60));
    if (result != 1)
      throw StateError('Text-to-speech could not play the reply.');
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<String?> _bestLocale(String languageCode) async {
    final prefix = const {'ta', 'hi', 'ml', 'kn'}.contains(languageCode)
        ? languageCode
        : 'en';
    try {
      final locales = await _speech.locales();
      final exact = locales.where(
        (locale) =>
            locale.localeId.toLowerCase().replaceAll('_', '-') == '$prefix-in',
      );
      if (exact.isNotEmpty) return exact.first.localeId;
      final matches = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith(prefix),
      );
      if (matches.isNotEmpty) return matches.first.localeId;
    } catch (_) {}
    return null;
  }

  Future<void> dispose() async {
    await cancelListening();
    _onListening = null;
    _onEnded = null;
    await stopSpeaking();
  }
}
