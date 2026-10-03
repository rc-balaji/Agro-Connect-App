import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum CygnusSpeechOutcome { completed, interrupted, cancelled }

class CygnusVoiceService {
  CygnusVoiceService({http.Client? client}) : _client = client ?? http.Client();

  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  final http.Client _client;

  static const String _gatewayUrl = String.fromEnvironment(
    'CYGNUS_GATEWAY_URL',
    defaultValue: 'https://agro-connect-cygnus.rcbalaji2003.workers.dev',
  );

  bool _initialized = false;
  bool _available = true;
  bool _listening = false;
  bool _processing = false;
  bool _speaking = false;
  bool _heardSpeech = false;
  bool _finishing = false;
  bool _bargeMonitoring = false;
  bool _bargeTriggering = false;

  Timer? _levelTimer;
  Timer? _hardStopTimer;
  Timer? _bargeTimer;
  DateTime? _startedAt;
  DateTime? _lastSpeechAt;
  DateTime? _bargeStartedAt;
  String? _recordingPath;
  String? _bargePath;
  String _languageCode = 'en';
  int _captureGeneration = 0;

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
    _available = true;

    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      // Live mode manages completion itself so that the microphone can remain
      // responsive to interruptions while audio is playing.
      await _tts.awaitSpeakCompletion(false);
    } catch (error) {
      debugPrint('Cygnus TTS initialization failed: $error');
    }
  }

  Future<void> startListening({
    required String languageCode,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    required ValueChanged<String> onError,
    required ValueChanged<double> onLevel,
    required ValueChanged<bool> onProcessing,
  }) async {
    await initialize();
    if (_listening || _processing || _finishing) return;

    final granted = await _recorder.hasPermission();
    if (!granted) {
      _available = false;
      onError('Microphone permission is required for voice input.');
      return;
    }
    _available = true;

    await _stopBargeMonitor();
    await stopSpeaking();

    final temp = await getTemporaryDirectory();
    final path = '${temp.path}/cygnus_${DateTime.now().millisecondsSinceEpoch}.m4a';

    _captureGeneration += 1;
    _languageCode = languageCode;
    _onPartial = onPartial;
    _onFinal = onFinal;
    _onError = onError;
    _onLevel = onLevel;
    _onProcessing = onProcessing;
    _recordingPath = path;
    _heardSpeech = false;
    _finishing = false;
    _startedAt = DateTime.now();
    _lastSpeechAt = null;

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _listening = true;
      onPartial('Listening…');
      onLevel(0.05);
      _startMeters();
      _hardStopTimer = Timer(const Duration(seconds: 30), () {
        unawaited(finishListening());
      });
    } catch (error) {
      _listening = false;
      _recordingPath = null;
      onLevel(0);
      onError('Could not start the microphone. Please try again.');
      debugPrint('Cygnus recorder start failed: $error');
    }
  }

  void _startMeters() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (!_listening || _finishing) return;
      try {
        final amp = await _recorder.getAmplitude();
        final level = ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
        _onLevel?.call(level);

        final now = DateTime.now();
        if (level >= 0.27) {
          _heardSpeech = true;
          _lastSpeechAt = now;
        }

        final started = _startedAt;
        final lastSpeech = _lastSpeechAt;
        if (_heardSpeech && started != null && lastSpeech != null) {
          final hasEnoughAudio = now.difference(started) >= const Duration(milliseconds: 900);
          final silenceReached = now.difference(lastSpeech) >= const Duration(milliseconds: 1250);
          if (hasEnoughAudio && silenceReached) {
            unawaited(finishListening());
          }
        }
      } catch (_) {
        // Metering is cosmetic; recording/transcription can continue.
      }
    });
  }

  Future<void> finishListening() async {
    if (_finishing || !_listening) return;
    _finishing = true;
    final generation = _captureGeneration;
    _levelTimer?.cancel();
    _hardStopTimer?.cancel();
    _onLevel?.call(0);

    String? path;
    try {
      path = await _recorder.stop();
    } catch (error) {
      debugPrint('Cygnus recorder stop failed: $error');
    }

    _listening = false;
    _processing = true;
    _onProcessing?.call(true);
    _onPartial?.call('Understanding your voice…');

    try {
      final actualPath = path ?? _recordingPath;
      if (actualPath == null || !File(actualPath).existsSync()) {
        throw const FormatException('No voice recording was created.');
      }
      final file = File(actualPath);
      if (await file.length() < 700) {
        throw const FormatException('Voice recording was too short.');
      }
      final transcript = await _transcribe(actualPath, _languageCode);
      if (generation != _captureGeneration) return;
      if (transcript.trim().isEmpty) {
        throw const FormatException('No speech was detected.');
      }
      _onFinal?.call(transcript.trim());
    } catch (error) {
      if (generation == _captureGeneration) {
        debugPrint('Cygnus transcription failed: $error');
        _onError?.call(_friendlyVoiceError(error));
      }
    } finally {
      final cleanup = path ?? _recordingPath;
      if (cleanup != null) {
        try {
          final file = File(cleanup);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
      if (generation == _captureGeneration) {
        _recordingPath = null;
        _processing = false;
        _finishing = false;
        _onProcessing?.call(false);
        _onLevel?.call(0);
      }
    }
  }

  Future<void> cancelListening() async {
    _captureGeneration += 1;
    _levelTimer?.cancel();
    _hardStopTimer?.cancel();
    _listening = false;
    _processing = false;
    _finishing = false;
    _onProcessing?.call(false);
    _onLevel?.call(0);
    try {
      await _recorder.cancel();
    } catch (_) {}
    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  Future<String> _transcribe(String path, String languageCode) async {
    String? firebaseToken;
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      firebaseToken = await auth.currentUser?.getIdToken();
    } catch (_) {
      throw StateError('Could not create a secure app session.');
    }

    final uri = Uri.parse('${_gatewayUrl.replaceAll(RegExp(r'/+$'), '')}/v1/transcribe');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields['language_code'] = languageCode
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          path,
          filename: 'cygnus-voice.m4a',
        ),
      );
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $firebaseToken';
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 28));
    } catch (_) {
      throw const SocketException('Voice service is unreachable.');
    }

    final body = await response.stream.bytesToString();
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(body);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final err = decoded['error'];
      final message = err is Map ? err['message']?.toString() : null;
      throw StateError(message ?? 'Voice transcription failed (${response.statusCode}).');
    }
    return decoded['text']?.toString() ?? '';
  }

  String _friendlyVoiceError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('unauthorized') || raw.contains('session')) {
      return 'Voice service could not verify this app session. Reopen the app and try again.';
    }
    if (raw.contains('rate') || raw.contains('busy')) {
      return 'Voice recognition is busy right now. Try again in a moment.';
    }
    if (raw.contains('short') || raw.contains('no speech')) {
      return 'I couldn’t hear enough speech. Try again and speak naturally.';
    }
    if (raw.contains('network') || raw.contains('unreachable') || raw.contains('socket')) {
      return 'Voice recognition needs an internet connection. Check your connection and try again.';
    }
    return 'I couldn’t understand that voice message. Please try once more.';
  }

  Future<void> speak(String text, String languageCode) async {
    if (text.trim().isEmpty) return;
    await initialize();
    await _stopBargeMonitor();
    try {
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
    final granted = await _recorder.hasPermission();
    if (!granted) return;

    final temp = await getTemporaryDirectory();
    final path = '${temp.path}/cygnus_barge_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _bargePath = path;
    _bargeBaseline = 0;
    _bargeBaselineSamples = 0;
    _bargeHits = 0;
    _bargeStartedAt = DateTime.now();

    try {
      await _recorder.start(
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
        final amp = await _recorder.getAmplitude();
        final level = ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
        final elapsed = DateTime.now().difference(_bargeStartedAt ?? DateTime.now());

        // Let acoustic echo cancellation settle before evaluating speech.
        if (elapsed < const Duration(milliseconds: 650)) {
          _bargeBaseline += level;
          _bargeBaselineSamples += 1;
          return;
        }

        if (_bargeBaselineSamples < 10) {
          _bargeBaseline += level;
          _bargeBaselineSamples += 1;
        }
        final baseline = _bargeBaselineSamples == 0 ? 0.16 : _bargeBaseline / _bargeBaselineSamples;
        final threshold = (baseline + 0.23).clamp(0.46, 0.76).toDouble();

        if (level >= threshold) {
          _bargeHits += 1;
        } else {
          _bargeHits = 0;
        }

        // Several consecutive peaks prevents the assistant's own speaker audio
        // from accidentally interrupting itself on most Android devices.
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
        await _recorder.cancel();
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
    // Prefer the script actually used in the reply. This keeps Live voice
    // natural when the user switches language mid-conversation without first
    // changing a settings toggle.
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta-IN';
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi-IN';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml-IN';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn-IN';

    // Latin-script Tanglish is usually pronounced more clearly by an Indian
    // English voice than by feeding romanized Tamil to a Tamil-script voice.
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
    await cancelListening();
    await stopSpeaking();
    await _recorder.dispose();
    _client.close();
  }
}
