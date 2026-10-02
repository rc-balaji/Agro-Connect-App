import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class CygnusVoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _available = false;

  bool get available => _available;
  bool get listening => _speech.isListening;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _available = await _speech.initialize(
        onError: (error) => debugPrint('Cygnus speech error: $error'),
        onStatus: (status) => debugPrint('Cygnus speech status: $status'),
        options: <SpeechConfigOption>[
          SpeechToText.androidNoBluetooth,
        ],
      );
    } catch (error) {
      debugPrint('Speech initialization failed: $error');
      _available = false;
    }

    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (error) {
      debugPrint('TTS initialization failed: $error');
    }
  }

  Future<void> startListening({
    required String languageCode,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
  }) async {
    await initialize();
    if (!_available || _speech.isListening) return;

    final locale = await _bestLocale(languageCode);
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        if (result.finalResult) {
          onFinal(words);
        } else {
          onPartial(words);
        }
      },
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        listenMode: ListenMode.confirmation,
        listenFor: const Duration(seconds: 24),
        pauseFor: const Duration(seconds: 3),
        localeId: locale,
      ),
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  Future<void> speak(String text, String languageCode) async {
    if (text.trim().isEmpty) return;
    await initialize();
    try {
      await _tts.stop();
      await _tts.setLanguage(_ttsLocale(languageCode));
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Cygnus TTS failed: $error');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<String?> _bestLocale(String languageCode) async {
    final preferredPrefix = switch (languageCode) {
      'ta' => 'ta',
      'hi' => 'hi',
      'ml' => 'ml',
      'kn' => 'kn',
      _ => 'en',
    };
    try {
      final locales = await _speech.locales();
      final exact = locales.where((locale) {
        final lower = locale.localeId.toLowerCase();
        return lower == '${preferredPrefix}_in' ||
            lower == '${preferredPrefix}-in';
      });
      if (exact.isNotEmpty) return exact.first.localeId;
      final prefixed = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith(preferredPrefix),
      );
      if (prefixed.isNotEmpty) return prefixed.first.localeId;
    } catch (_) {}
    return null;
  }

  String _ttsLocale(String code) => switch (code) {
        'ta' => 'ta-IN',
        'hi' => 'hi-IN',
        'ml' => 'ml-IN',
        'kn' => 'kn-IN',
        _ => 'en-IN',
      };

  Future<void> dispose() async {
    await cancelListening();
    await stopSpeaking();
  }
}
