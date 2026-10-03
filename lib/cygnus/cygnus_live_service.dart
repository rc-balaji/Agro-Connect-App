import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// A foreground-only, bidirectional audio session. No audio is saved to disk.
class CygnusLiveService {
  static const modelName = String.fromEnvironment(
    'CYGNUS_LIVE_MODEL',
    defaultValue: 'gemini-3.1-flash-live-preview',
  );
  AudioRecorder? _recorder;
  LiveSession? _session;
  StreamSubscription<Uint8List>? _microphone;
  AudioSource? _output;
  int _generation = 0;
  Future<void>? _stopping;
  bool _audioInitialized = false;

  Future<void> start({
    required String instruction,
    required List<Tool> tools,
    required Future<Map<String, Object?>> Function(String, Map<String, Object?>)
    onTool,
    required void Function(String) onStatus,
    required void Function(String, bool) onTranscript,
    required void Function(Object) onError,
  }) async {
    await stop();
    final generation = ++_generation;
    bool current() => generation == _generation;
    try {
      onStatus('Connecting Live audio…');
      final recorder = AudioRecorder();
      _recorder = recorder;
      if (!await recorder.hasPermission()) {
        throw StateError('Microphone permission is required for Live audio.');
      }
      if (!current()) return;
      await SoLoud.instance.init(sampleRate: 24000, channels: Channels.mono);
      _audioInitialized = true;
      if (!current()) {
        await stop();
        return;
      }
      final connection = FirebaseAI.googleAI()
          .liveGenerativeModel(
            model: modelName,
            systemInstruction: Content.system(instruction),
            tools: tools,
            liveGenerationConfig: LiveGenerationConfig(
              responseModalities: [ResponseModalities.audio],
              inputAudioTranscription: AudioTranscriptionConfig(),
              outputAudioTranscription: AudioTranscriptionConfig(),
            ),
          )
          .connect();
      // A late connection must not leave a billable socket open after Stop.
      unawaited(
        connection.then((session) async {
          if (!current()) await session.close();
        }, onError: (Object _) {}),
      );
      final session = await connection.timeout(const Duration(seconds: 20));
      if (!current()) {
        await session.close();
        return;
      }
      _session = session;
      await _resetOutput();
      if (!current()) return;
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
        ),
      );
      if (!current()) {
        await recorder.stop();
        return;
      }
      _microphone = stream
          .asyncMap((data) async {
            if (current()) {
              await session.sendAudioRealtime(
                InlineDataPart('audio/pcm;rate=16000', data),
              );
            }
            return data;
          })
          .listen(
            (_) {},
            onError: (Object error) {
              if (current()) {
                onError(error);
                unawaited(stop());
              }
            },
          );
      onStatus('Live · listening — speak naturally');
      unawaited(
        _receive(session, current, onStatus, onTranscript, onTool, onError),
      );
    } catch (error) {
      if (current()) {
        onError(error);
        await stop();
      }
    }
  }

  Future<void> _receive(
    LiveSession session,
    bool Function() current,
    void Function(String) onStatus,
    void Function(String, bool) onTranscript,
    Future<Map<String, Object?>> Function(String, Map<String, Object?>) onTool,
    void Function(Object) onError,
  ) async {
    var input = '';
    var output = '';
    final results = <String, Map<String, Object?>>{};
    void flush() {
      if (input.trim().isNotEmpty) onTranscript(input.trim(), true);
      if (output.trim().isNotEmpty) onTranscript(output.trim(), false);
      input = '';
      output = '';
    }

    try {
      await for (final response in session.receive()) {
        if (!current()) break;
        final message = response.message;
        if (message is LiveServerContent) {
          input += message.inputTranscription?.text ?? '';
          output += message.outputTranscription?.text ?? '';
          if (message.interrupted == true) {
            await _resetOutput();
            if (!current()) break;
            flush();
            onStatus('Live · listening');
          }
          for (final part in message.modelTurn?.parts ?? <Part>[]) {
            if (part is InlineDataPart &&
                part.mimeType.startsWith('audio/pcm')) {
              final source = _output;
              if (source != null)
                SoLoud.instance.addAudioDataStream(source, part.bytes);
              onStatus('Live · speaking — you can interrupt');
            }
          }
          if (message.turnComplete == true) {
            flush();
            onStatus('Live · ready for your next question');
          }
        } else if (message is LiveServerToolCall) {
          final replies = <FunctionResponse>[];
          for (final call in message.functionCalls ?? <FunctionCall>[]) {
            if (!current()) break;
            final id = call.id;
            final result = id != null && results.containsKey(id)
                ? results[id]!
                : await onTool(call.name, call.args);
            if (id != null) results[id] = result;
            replies.add(FunctionResponse(call.name, result, id: id));
          }
          if (current() && replies.isNotEmpty)
            await session.sendToolResponse(replies);
        } else if (message is GoingAwayNotice) {
          throw StateError(
            'Live session limit reached. Tap Live to start again.',
          );
        }
      }
      if (current()) {
        flush();
        onError(StateError('Live connection closed. Tap Live to reconnect.'));
      }
    } catch (error) {
      if (current()) onError(error);
    } finally {
      if (current()) await stop();
    }
  }

  Future<void> _resetOutput() async {
    final previous = _output;
    _output = null;
    if (previous != null) await SoLoud.instance.disposeSource(previous);
    if (!_audioInitialized) return;
    final source = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.08,
      sampleRate: 24000,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _output = source;
    SoLoud.instance.play(source);
  }

  Future<void> stop() {
    ++_generation;
    return _stopping ??= _stop().whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    final mic = _microphone;
    _microphone = null;
    final recorder = _recorder;
    _recorder = null;
    final session = _session;
    _session = null;
    final output = _output;
    _output = null;
    try {
      await mic?.cancel();
    } catch (_) {}
    try {
      await recorder?.stop();
    } catch (_) {}
    try {
      await recorder?.dispose();
    } catch (_) {}
    try {
      await session?.close();
    } catch (_) {}
    try {
      if (output != null) await SoLoud.instance.disposeSource(output);
    } catch (_) {}
    if (_audioInitialized) {
      SoLoud.instance.deinit();
      _audioInitialized = false;
    }
  }
}
