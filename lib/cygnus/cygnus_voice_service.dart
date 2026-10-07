import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum CygnusSpeechOutcome { completed, interrupted, cancelled }

class CygnusVoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _bargeRecorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _available = false;
  bool _listening = false;
  bool _processing = false;
  bool _speaking = false;
  bool _finalSubmitted = false;
  bool _finishing = false;
  bool _bargeMonitoring = false;
  bool _bargeTriggering = false;

  Timer? _finalFallbackTimer;
  Timer? _restartListeningTimer;
  Timer? _bargeTimer;
  DateTime? _bargeStartedAt;
  String? _bargePath;
  String _latestWords = '';
  String _committedWords = '';
  String _currentWords = '';
  String? _activeLocaleId;
  bool _manualStopRequired = false;
  double _minSound = 999;
  double _maxSound = -999;

  double _bargeBaseline = 0.0;
  int _bargeBaselineSamples = 0;
  int _bargeHits = 0;
  Completer<CygnusSpeechOutcome>? _speechCompleter;
  ValueChanged<bool>? _speechStateCallback;

  ValueChanged<String>? _onPartial;
  ValueChanged<String>? _onFinal;
  ValueChanged<String>? _onError;
  ValueChanged<double>? _onLevel;
  ValueChanged<bool>? _onProcessing;

  bool get available => _available;
  bool get listening => _listening;
  bool get processing => _processing;
  bool get speaking => _speaking;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) {
          if (!_listening && !_processing) return;
          debugPrint('Cygnus native speech error: ${error.errorMsg}');
          final reportError = !_finalSubmitted;
          _restartListeningTimer?.cancel();
          _finalSubmitted = true;
          _listening = false;
          _processing = false;
          _finishing = false;
          _onProcessing?.call(false);
          _onLevel?.call(0);
          if (reportError) {
            _onError?.call(_friendlySpeechError(error.errorMsg));
          }
        },
        options: <stt.SpeechConfigOption>[
          stt.SpeechToText.androidAlwaysUseStop,
          stt.SpeechToText.androidNoBluetooth,
        ],
      );
    } catch (error) {
      _available = false;
      debugPrint('Cygnus native speech initialization failed: $error');
    }

    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (error) {
      debugPrint('Cygnus TTS initialization failed: $error');
    }
  }

  Future<void> startListening({
    required String languageCode,
    required bool liveConversation,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    required ValueChanged<String> onError,
    required ValueChanged<double> onLevel,
    required ValueChanged<bool> onProcessing,
  }) async {
    await initialize();
    if (_listening || _processing || _finishing) return;

    if (!_available) {
      onError('Voice recognition is not available on this device.');
      return;
    }

    await _stopBargeMonitor();
    await stopSpeaking();

    _onPartial = onPartial;
    _onFinal = onFinal;
    _onError = onError;
    _onLevel = onLevel;
    _onProcessing = onProcessing;
    _latestWords = '';
    _committedWords = '';
    _currentWords = '';
    _manualStopRequired = !liveConversation;
    _finalSubmitted = false;
    _finishing = false;
    _processing = false;
    _minSound = 999;
    _maxSound = -999;

    final localeId = await _preferredLocale(languageCode);
    _activeLocaleId = localeId;

    try {
      await _startRecognition(localeId, showListeningPrompt: true);
    } catch (error) {
      _listening = false;
      _processing = false;
      _finishing = false;
      onLevel(0);
      onError('Could not start voice recognition. Please try again.');
      debugPrint('Cygnus native speech start failed: $error');
    }
  }

  Future<void> _startRecognition(
    String? localeId, {
    bool showListeningPrompt = false,
  }) async {
    _listening = true;
    if (showListeningPrompt) {
      _onPartial?.call('Listening…');
      _onLevel?.call(0.04);
    }

    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;

        if (_manualStopRequired) {
          _currentWords = words;
          _latestWords = [
            _committedWords,
            _currentWords,
          ].where((part) => part.isNotEmpty).join(' ');
          if (result.finalResult) {
            _committedWords = _latestWords;
            _currentWords = '';
          }
          _onPartial?.call(_latestWords);
          return;
        }

        _latestWords = words;
        _onPartial?.call(words);
        if (result.finalResult) _emitFinal(words);
      },
      onSoundLevelChange: _handleSoundLevel,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        onDevice: false,
        listenMode: stt.ListenMode.dictation,
        pauseFor: _manualStopRequired ? null : const Duration(seconds: 3),
        listenFor: _manualStopRequired ? null : const Duration(seconds: 45),
        localeId: localeId,
        contextualPhrases: const <String>[
          'Cygnus',
          'Agro Connect',
          'motor one',
          'motor two',
          'motor three',
          'temperature',
          'humidity',
          'soil moisture',
          'water level',
          'schedule',
          'plant health',
        ],
      ),
    );
  }

  void _handleSoundLevel(double raw) {
    if (!_listening) return;
    if (raw < _minSound) _minSound = raw;
    if (raw > _maxSound) _maxSound = raw;
    final range = (_maxSound - _minSound).abs();
    final normalized = range < 0.8
        ? 0.12
        : ((raw - _minSound) / range).clamp(0.03, 1.0).toDouble();
    _onLevel?.call(normalized);
  }

  void _handleSpeechStatus(String status) {
    final done =
        status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus;
    if (!done) return;

    _listening = false;
    _onLevel?.call(0);

    if (_manualStopRequired && !_finishing && !_finalSubmitted) {
      if (!_restartListeningTimerActive) {
        _restartListeningTimer = Timer(const Duration(milliseconds: 250), () {
          _restartListeningTimer = null;
          unawaited(_resumeManualListening());
        });
      }
      return;
    }

    if (_latestWords.isNotEmpty && !_finalSubmitted) {
      _finalFallbackTimer?.cancel();
      _finalFallbackTimer = Timer(const Duration(milliseconds: 90), () {
        if (!_finalSubmitted && _latestWords.isNotEmpty) {
          _emitFinal(_latestWords);
        }
      });
    } else if (_finishing) {
      _finishing = false;
      _processing = false;
      _onProcessing?.call(false);
    }
  }

  Future<void> _resumeManualListening() async {
    final localeId = _activeLocaleId;
    if (!_manualStopRequired || _finishing || _finalSubmitted || _listening) {
      return;
    }

    try {
      await _startRecognition(localeId);
    } catch (error) {
      _listening = false;
      _onLevel?.call(0);
      _onError?.call('Voice recognition stopped. Tap the mic and try again.');
      debugPrint('Cygnus voice listening restart failed: $error');
    }
  }

  bool get _restartListeningTimerActive =>
      _restartListeningTimer?.isActive ?? false;

  void _emitFinal(String text) {
    final clean = text.trim();
    if (clean.isEmpty || _finalSubmitted) return;
    _finalSubmitted = true;
    _finalFallbackTimer?.cancel();
    _restartListeningTimer?.cancel();
    _listening = false;
    _processing = false;
    _finishing = false;
    _onProcessing?.call(false);
    _onLevel?.call(0);
    _onFinal?.call(clean);
  }

  Future<void> finishListening() async {
    if (_finalSubmitted) return;
    if (!_listening && !_speech.isListening) {
      if (_latestWords.isNotEmpty)
        _emitFinal(_latestWords);
      else {
        _restartListeningTimer?.cancel();
        _finishing = false;
        _processing = false;
        _onProcessing?.call(false);
        _onError?.call(
          'I couldn’t hear enough speech. Try again and speak naturally.',
        );
      }
      return;
    }

    _restartListeningTimer?.cancel();
    _finishing = true;
    _processing = true;
    _onProcessing?.call(true);
    _onLevel?.call(0);

    try {
      await _speech.stop();
    } catch (error) {
      debugPrint('Cygnus native speech stop failed: $error');
    }

    _finalFallbackTimer?.cancel();
    _finalFallbackTimer = Timer(const Duration(milliseconds: 320), () {
      if (_finalSubmitted) return;
      if (_latestWords.isNotEmpty) {
        _emitFinal(_latestWords);
      } else {
        _finishing = false;
        _processing = false;
        _onProcessing?.call(false);
        _onError?.call(
          'I couldn’t hear enough speech. Try again and speak naturally.',
        );
      }
    });
  }

  Future<void> cancelListening() async {
    _finalFallbackTimer?.cancel();
    _restartListeningTimer?.cancel();
    _latestWords = '';
    _committedWords = '';
    _currentWords = '';
    _finalSubmitted = true;
    _listening = false;
    _processing = false;
    _finishing = false;
    _onProcessing?.call(false);
    _onLevel?.call(0);
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  Future<String?> _preferredLocale(String languageCode) async {
    final wanted = switch (languageCode) {
      'ta' => const <String>['ta_IN', 'ta-IN', 'ta'],
      'hi' => const <String>['hi_IN', 'hi-IN', 'hi'],
      'ml' => const <String>['ml_IN', 'ml-IN', 'ml'],
      'kn' => const <String>['kn_IN', 'kn-IN', 'kn'],
      _ => const <String>['en_IN', 'en-IN', 'en'],
    };

    try {
      final locales = await _speech.locales();
      for (final desired in wanted) {
        final normalizedDesired = desired.toLowerCase().replaceAll('-', '_');
        for (final locale in locales) {
          final normalizedLocale = locale.localeId.toLowerCase().replaceAll(
            '-',
            '_',
          );
          if (normalizedLocale == normalizedDesired ||
              normalizedLocale.startsWith(
                '${normalizedDesired.split('_').first}_',
              )) {
            return locale.localeId;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _friendlySpeechError(String rawError) {
    final raw = rawError.toLowerCase();
    if (raw.contains('permission')) {
      return 'Microphone and speech permission are required for voice input.';
    }
    if (raw.contains('network')) {
      return 'Voice recognition needs a working internet connection on this device.';
    }
    if (raw.contains('no_match') || raw.contains('nomatch')) {
      return 'I couldn’t catch that clearly. Try once more and speak naturally.';
    }
    if (raw.contains('busy')) {
      return 'Voice recognition is busy. Wait a moment and try again.';
    }
    return 'I couldn’t understand that voice input. Please try again.';
  }

  Future<void> speak(String text, String languageCode) async {
    if (text.trim().isEmpty) return;
    await initialize();
    await _stopBargeMonitor();
    try {
      await _speech.cancel();
      await _tts.stop();
      await _tts.setLanguage(_ttsLocaleForText(text, languageCode));
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Cygnus TTS failed: $error');
    }
  }

  Future<CygnusSpeechOutcome> speakInteractive(
    String text,
    String languageCode, {
    required Future<void> Function() onBargeIn,
    ValueChanged<bool>? onSpeaking,
  }) async {
    if (text.trim().isEmpty) return CygnusSpeechOutcome.completed;
    await initialize();
    await cancelListening();
    await _stopBargeMonitor();
    await _tts.stop();

    _speaking = true;
    _bargeTriggering = false;
    _speechStateCallback = onSpeaking;
    _speechStateCallback?.call(true);
    final completer = Completer<CygnusSpeechOutcome>();
    _speechCompleter = completer;

    Future<void> finish(CygnusSpeechOutcome outcome) async {
      if (_speechCompleter != completer || completer.isCompleted) return;
      await _stopBargeMonitor();
      _speaking = false;
      _speechStateCallback?.call(false);
      _speechStateCallback = null;
      completer.complete(outcome);
    }

    _tts.setCompletionHandler(() {
      unawaited(finish(CygnusSpeechOutcome.completed));
    });
    _tts.setCancelHandler(() {
      if (!_bargeTriggering) {
        unawaited(finish(CygnusSpeechOutcome.cancelled));
      }
    });
    _tts.setErrorHandler((_) {
      unawaited(finish(CygnusSpeechOutcome.cancelled));
    });

    try {
      await _tts.setLanguage(_ttsLocaleForText(text, languageCode));
      await _tts.speak(text);
      await _startBargeMonitor(() async {
        if (_bargeTriggering || !_speaking) return;
        _bargeTriggering = true;
        await _stopBargeMonitor();
        try {
          await _tts.stop();
        } catch (_) {}
        await onBargeIn();
        _bargeTriggering = false;
        await finish(CygnusSpeechOutcome.interrupted);
      });
    } catch (error) {
      debugPrint('Cygnus interactive TTS failed: $error');
      await finish(CygnusSpeechOutcome.cancelled);
    }

    return completer.future.timeout(
      const Duration(seconds: 70),
      onTimeout: () {
        unawaited(stopSpeaking());
        return CygnusSpeechOutcome.cancelled;
      },
    );
  }

  Future<void> _startBargeMonitor(Future<void> Function() onDetected) async {
    if (_bargeMonitoring || _listening || _processing) return;
    final granted = await _bargeRecorder.hasPermission();
    if (!granted) return;

    final temp = await getTemporaryDirectory();
    final path =
        '${temp.path}/cygnus_barge_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _bargePath = path;
    _bargeBaseline = 0;
    _bargeBaselineSamples = 0;
    _bargeHits = 0;
    _bargeStartedAt = DateTime.now();

    try {
      await _bargeRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _bargeMonitoring = true;
    } catch (error) {
      debugPrint('Cygnus barge-in monitor unavailable: $error');
      _bargePath = null;
      return;
    }

    _bargeTimer?.cancel();
    _bargeTimer = Timer.periodic(const Duration(milliseconds: 75), (_) async {
      if (!_bargeMonitoring || _bargeTriggering || !_speaking) return;
      try {
        final amp = await _bargeRecorder.getAmplitude();
        final level = ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
        final elapsed = DateTime.now().difference(
          _bargeStartedAt ?? DateTime.now(),
        );

        if (elapsed < const Duration(milliseconds: 650)) {
          _bargeBaseline += level;
          _bargeBaselineSamples += 1;
          return;
        }

        if (_bargeBaselineSamples < 10) {
          _bargeBaseline += level;
          _bargeBaselineSamples += 1;
        }
        final baseline = _bargeBaselineSamples == 0
            ? 0.16
            : _bargeBaseline / _bargeBaselineSamples;
        final threshold = (baseline + 0.23).clamp(0.46, 0.76).toDouble();

        if (level >= threshold) {
          _bargeHits += 1;
        } else {
          _bargeHits = 0;
        }

        if (_bargeHits >= 3) {
          _bargeHits = 0;
          unawaited(onDetected());
        }
      } catch (_) {}
    });
  }

  Future<void> _stopBargeMonitor() async {
    _bargeTimer?.cancel();
    _bargeTimer = null;
    if (_bargeMonitoring) {
      _bargeMonitoring = false;
      try {
        await _bargeRecorder.cancel();
      } catch (_) {}
    }
    final path = _bargePath;
    _bargePath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> stopSpeaking() async {
    await _stopBargeMonitor();
    final completer = _speechCompleter;
    _speechCompleter = null;
    try {
      await _tts.stop();
    } catch (_) {}
    if (_speaking) {
      _speaking = false;
      _speechStateCallback?.call(false);
      _speechStateCallback = null;
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(CygnusSpeechOutcome.cancelled);
    }
  }

  String _ttsLocaleForText(String text, String fallbackCode) {
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta-IN';
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi-IN';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml-IN';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn-IN';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en-IN';
    return _ttsLocale(fallbackCode);
  }

  String _ttsLocale(String code) => switch (code) {
    'ta' => 'ta-IN',
    'hi' => 'hi-IN',
    'ml' => 'ml-IN',
    'kn' => 'kn-IN',
    _ => 'en-IN',
  };

  Future<void> dispose() async {
    _finalFallbackTimer?.cancel();
    _restartListeningTimer?.cancel();
    await cancelListening();
    await stopSpeaking();
    await _bargeRecorder.dispose();
  }
}
