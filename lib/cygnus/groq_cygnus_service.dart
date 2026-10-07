import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cygnus_models.dart';

typedef CygnusToolExecutor =
    Future<Map<String, Object?>> Function(
      String name,
      Map<String, Object?> arguments,
    );

class GroqCygnusException implements Exception {
  const GroqCygnusException({
    required this.message,
    this.code = 'gateway_error',
    this.statusCode,
  });

  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => 'GroqCygnusException($code, $statusCode): $message';
}

class GroqCygnusService {
  GroqCygnusService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String gatewayUrl = String.fromEnvironment(
    'CYGNUS_GATEWAY_URL',
    defaultValue: 'https://agro-connect-cygnus.rcbalaji2003.workers.dev',
  );

  static const String primaryModel = 'openai/gpt-oss-120b';
  static const String fastModel = 'openai/gpt-oss-20b';

  Future<String> runAgent({
    required String systemInstruction,
    required List<CygnusMessage> conversation,
    required List<Map<String, dynamic>> tools,
    required CygnusToolExecutor executeTool,
    required String model,
    required String reasoningEffort,
  }) async {
    final messages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemInstruction},
      ..._conversationMessages(conversation),
    ];
    String? lastSuccessfulTool;
    Map<String, Object?>? lastSuccessfulResult;

    for (var round = 0; round < 6; round++) {
      late final Map<String, dynamic> response;
      try {
        response = await _request(
          model: model,
          reasoningEffort: reasoningEffort,
          messages: messages,
          tools: tools,
        );
      } on GroqCygnusException catch (error) {
        if (error.statusCode == 429 && lastSuccessfulTool != null) {
          final result = lastSuccessfulResult;
          if (result == null) rethrow;
          final fallback = _toolFallbackReply(lastSuccessfulTool, result);
          if (fallback != null) return fallback;
        }
        rethrow;
      }

      final choice = _firstChoice(response);
      final message = _asMap(choice['message']);
      final toolCalls = _asList(message['tool_calls'])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

      if (toolCalls.isEmpty) {
        final text = message['content']?.toString().trim() ?? '';
        return text.isEmpty ? 'Done.' : text;
      }

      messages.add(<String, dynamic>{
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': toolCalls,
      });

      final clarificationCalls = toolCalls
          .where((call) {
            final function = _asMap(call['function']);
            return function['name'] == 'request_clarification';
          })
          .toList(growable: false);
      final callsToExecute = clarificationCalls.isEmpty
          ? toolCalls
          : clarificationCalls.take(1);
      for (final call in callsToExecute) {
        final function = _asMap(call['function']);
        final name = function['name']?.toString() ?? '';
        final rawArgs = function['arguments']?.toString() ?? '{}';
        final args = _decodeArguments(rawArgs);

        Map<String, Object?> result;
        if (name.isEmpty) {
          result = <String, Object?>{
            'ok': false,
            'message': 'Invalid tool request.',
          };
        } else {
          result = await executeTool(name, args);
        }
        lastSuccessfulTool = null;
        lastSuccessfulResult = null;
        if (result['ok'] == true) {
          lastSuccessfulTool = name;
          lastSuccessfulResult = result;
        }

        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call['id']?.toString() ?? '',
          'name': name,
          'content': jsonEncode(result),
        });
        if (name == 'request_clarification' &&
            result['awaitingClarification'] != true) {
          throw GroqCygnusException(
            code: 'clarification_not_saved',
            message:
                result['message']?.toString() ??
                'Cygnus could not save the clarification request.',
          );
        }
        if (result['awaitingClarification'] == true) {
          final question = result['question']?.toString().trim() ?? '';
          if (question.isEmpty) {
            throw const GroqCygnusException(
              code: 'invalid_clarification',
              message: 'Cygnus could not form a clarification question.',
            );
          }
          return question;
        }
      }
    }

    throw const GroqCygnusException(
      code: 'tool_loop_limit',
      message: 'Cygnus reached the action limit for this request.',
    );
  }

  String? _toolFallbackReply(String name, Map<String, Object?> result) {
    if (name == 'get_current_status') {
      if (result['deviceOnline'] != true) {
        return 'The farm device is offline, so current readings are not available.';
      }
      String reading(String key, String label, String unit) {
        final value = result[key];
        if (value is! num) return '';
        return '$label ${value.toStringAsFixed(1)}$unit';
      }

      final readings = <String>[
        reading('temperatureC', 'temperature', '°C'),
        reading('humidityPercent', 'humidity', '%'),
        reading('soilPercent', 'soil moisture', '%'),
        reading('waterPercent', 'water level', '%'),
      ].where((value) => value.isNotEmpty).toList(growable: false);
      if (readings.isEmpty) return null;
      return 'Current farm readings: ${readings.join(', ')}.';
    }

    if (name == 'get_metric_trend') {
      final metric = switch (result['metric']) {
        'temperature' => 'temperature',
        'humidity' => 'humidity',
        'soil' => 'soil moisture',
        'water' => 'water level',
        _ => null,
      };
      final latest = result['latest'];
      final average = result['average'];
      if (metric == null || latest is! num || average is! num) return null;
      final unit = metric == 'temperature' ? '°C' : '%';
      return 'Recent $metric trend: latest ${latest.toStringAsFixed(1)}$unit, '
          'average ${average.toStringAsFixed(1)}$unit.';
    }

    final message = result['message']?.toString().trim() ?? '';
    return message.isEmpty ? null : message;
  }

  Future<Map<String, dynamic>> _request({
    required String model,
    required String reasoningEffort,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final uri = Uri.parse(
      '${gatewayUrl.replaceAll(RegExp(r'/+$'), '')}/v1/chat',
    );

    String? firebaseToken;
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      firebaseToken = await auth.currentUser?.getIdToken();
    } catch (error) {
      debugPrint('Cygnus Firebase auth token unavailable: $error');
    }

    final body = <String, dynamic>{
      'model': model,
      'reasoning_effort': reasoningEffort,
      'messages': messages,
      'tools': tools,
    };

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (firebaseToken != null && firebaseToken.isNotEmpty)
                'Authorization': 'Bearer $firebaseToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 28));
    } catch (error) {
      throw GroqCygnusException(
        code: 'network_error',
        message: 'Could not reach the Cygnus AI gateway.',
      );
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) decoded = Map<String, dynamic>.from(raw);
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _asMap(decoded['error']);
      final code = error['code']?.toString() ?? 'gateway_error';
      final message =
          error['message']?.toString() ??
          'Cygnus AI gateway returned ${response.statusCode}.';
      throw GroqCygnusException(
        code: code,
        message: message,
        statusCode: response.statusCode,
      );
    }

    return decoded;
  }

  List<Map<String, dynamic>> _conversationMessages(
    List<CygnusMessage> conversation,
  ) {
    String? contentFor(CygnusMessage message) {
      if (message.kind == 'text') return message.text;
      if (message.kind == 'image' && message.role == 'user') {
        return '[The user uploaded a leaf image for local Plant Health analysis.]';
      }
      if (message.kind == 'leaf_result' && message.role == 'assistant') {
        final p = message.payload;
        final crop = p['crop']?.toString() ?? 'Plant';
        final condition = p['condition']?.toString() ?? 'Unknown condition';
        final confidence = (p['confidence'] as num?)?.toDouble();
        final pct = confidence == null
            ? 'unknown'
            : '${(confidence * 100).toStringAsFixed(0)}%';
        final treatment = _stringList(p['treatment']).take(4).join('; ');
        final prevention = _stringList(p['prevention']).take(4).join('; ');
        final symptoms = _stringList(p['symptoms']).take(4).join('; ');
        return '[Local Plant Health result — crop: $crop; condition: $condition; confidence: $pct; symptoms: $symptoms; treatment: $treatment; prevention: $prevention.]';
      }
      return null;
    }

    final eligible = conversation
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .map((message) => (message: message, content: contentFor(message)))
        .where(
          (item) => item.content != null && item.content!.trim().isNotEmpty,
        )
        .toList(growable: false);

    final recent = eligible.length > 20
        ? eligible.sublist(eligible.length - 20)
        : eligible;

    final result = <Map<String, dynamic>>[];
    String? lastRole;
    final buffer = <String>[];

    void flush() {
      if (lastRole == null || buffer.isEmpty) return;
      if (lastRole == 'assistant' && result.isEmpty) {
        buffer.clear();
        return;
      }
      result.add(<String, dynamic>{
        'role': lastRole,
        'content': buffer.join('\n'),
      });
      buffer.clear();
    }

    for (final item in recent) {
      final message = item.message;
      final content = item.content!;
      if (message.role != lastRole) {
        flush();
        lastRole = message.role;
      }
      buffer.add(content);
    }
    flush();
    return result;
  }

  List<String> _stringList(Object? value) {
    if (value is List)
      return value.map((e) => e.toString()).toList(growable: false);
    return const <String>[];
  }

  Map<String, Object?> _decodeArguments(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      }
    } catch (_) {}
    return <String, Object?>{};
  }

  Map<String, dynamic> _firstChoice(Map<String, dynamic> response) {
    final choices = _asList(response['choices']);
    if (choices.isEmpty || choices.first is! Map) {
      throw const GroqCygnusException(
        code: 'invalid_response',
        message: 'Cygnus received an invalid AI response.',
      );
    }
    return Map<String, dynamic>.from(choices.first as Map);
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  void dispose() => _client.close();
}
