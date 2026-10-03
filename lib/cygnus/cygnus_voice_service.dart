import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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
  bool _heardSpeech = false;
  bool _finishing = false;

  Timer? _levelTimer;
  Timer? _hardStopTimer;
  DateTime? _startedAt;
  DateTime? _lastSpeechAt;
  String? _recordingPath;
  String _languageCode = 'en';

  ValueChanged<String>? _onPartial;
  ValueChanged<String>? _onFinal;
  ValueChanged<String>? _onError;
  ValueChanged<double>? _onLevel;
  ValueChanged<bool>? _onProcessing;

  bool get available => _available;
  bool get listening => _listening;
  bool get processing => _processing;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Do not request microphone permission on app launch. Permission is
    // requested only when the user taps the microphone.
    _available = true;

    try {
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
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

    await stopSpeaking();

    final temp = await getTemporaryDirectory();
    final path = '${temp.path}/cygnus_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
      _hardStopTimer = Timer(const Duration(seconds: 25), () {
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
    _levelTimer = Timer.periodic(const Duration(milliseconds: 90), (_) async {
      if (!_listening || _finishing) return;
      try {
        final amp = await _recorder.getAmplitude();
        final level = ((amp.current + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
        _onLevel?.call(level);

        final now = DateTime.now();
        // A modest threshold keeps fan/room noise from ending a turn too early.
        if (level >= 0.30) {
          _heardSpeech = true;
          _lastSpeechAt = now;
        }

        final started = _startedAt;
        final lastSpeech = _lastSpeechAt;
        if (_heardSpeech && started != null && lastSpeech != null) {
          final hasEnoughAudio = now.difference(started) >= const Duration(milliseconds: 1100);
          final silenceReached = now.difference(lastSpeech) >= const Duration(milliseconds: 1450);
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
    if (_finishing || (!_listening && !_processing)) return;
    if (!_listening) return;
    _finishing = true;
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
      if (transcript.trim().isEmpty) {
        throw const FormatException('No speech was detected.');
      }
      _onFinal?.call(transcript.trim());
    } catch (error) {
      debugPrint('Cygnus transcription failed: $error');
      _onError?.call(_friendlyVoiceError(error));
    } finally {
      final cleanup = path ?? _recordingPath;
      if (cleanup != null) {
        try {
          final file = File(cleanup);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
      _recordingPath = null;
      _processing = false;
      _finishing = false;
      _onProcessing?.call(false);
      _onLevel?.call(0);
    }
  }

  Future<void> cancelListening() async {
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
    _recordingPath = null;
  }

  Future<String> _transcribe(String path, String languageCode) async {
    String? firebaseToken;
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      firebaseToken = await auth.currentUser?.getIdToken();
    } catch (error) {
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
      response = await _client.send(request).timeout(const Duration(seconds: 24));
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
      return 'I couldn’t hear enough speech. Hold the mic and speak naturally.';
    }
    if (raw.contains('network') || raw.contains('unreachable') || raw.contains('socket')) {
      return 'Voice recognition needs an internet connection. Check your connection and try again.';
    }
    return 'I couldn’t understand that voice message. Please try once more.';
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
