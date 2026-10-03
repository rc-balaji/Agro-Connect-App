import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cygnus_models.dart';

typedef CygnusToolExecutor = Future<Map<String, Object?>> Function(
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
      <String, dynamic>{
        'role': 'system',
        'content': systemInstruction,
      },
      ..._conversationMessages(conversation),
    ];

    for (var round = 0; round < 6; round++) {
      final response = await _request(
        model: model,
        reasoningEffort: reasoningEffort,
        messages: messages,
        tools: tools,
      );

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

      for (final call in toolCalls) {
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

        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call['id']?.toString() ?? '',
          'name': name,
          'content': jsonEncode(result),
        });
      }
    }

    throw const GroqCygnusException(
      code: 'tool_loop_limit',
      message: 'Cygnus reached the action limit for this request.',
    );
  }

  Future<Map<String, dynamic>> _request({
    required String model,
    required String reasoningEffort,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final uri = Uri.parse('${gatewayUrl.replaceAll(RegExp(r'/+$'), '')}/v1/chat');

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
      final message = error['message']?.toString() ??
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
    final eligible = conversation
        .where((message) =>
            message.kind == 'text' &&
            (message.role == 'user' || message.role == 'assistant'))
        .toList(growable: false);

    final recent = eligible.length > 16
        ? eligible.sublist(eligible.length - 16)
        : eligible;

    final result = <Map<String, dynamic>>[];
    String? lastRole;
    final buffer = <String>[];

    void flush() {
      if (lastRole == null || buffer.isEmpty) return;
      // Groq/OpenAI chat histories should begin with a user message. Skip the
      // initial welcome assistant message when rebuilding a session.
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

    for (final message in recent) {
      if (message.role != lastRole) {
        flush();
        lastRole = message.role;
      }
      buffer.add(message.text);
    }
    flush();
    return result;
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
