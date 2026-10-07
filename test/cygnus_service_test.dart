import 'dart:convert';

import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:agro_connect/cygnus/groq_cygnus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'uses successful live telemetry when the final AI response is rate limited',
    () async {
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'status-call',
                        'function': {
                          'name': 'get_current_status',
                          'arguments': jsonEncode({'live': true}),
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'rate_limit',
              'message': 'Cygnus is busy right now.',
            },
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GroqCygnusService(client: client);

      final reply = await service.runAgent(
        systemInstruction: 'Test instruction',
        conversation: [
          CygnusMessage(
            id: 'user-1',
            role: 'user',
            text: 'What is the current water level?',
            createdAt: DateTime.now(),
          ),
        ],
        tools: const [],
        executeTool: (name, arguments) async => {
          'ok': true,
          'deviceOnline': true,
          'temperatureC': 27.4,
          'humidityPercent': 61,
          'soilPercent': 43,
          'waterPercent': 72,
        },
        model: GroqCygnusService.fastModel,
        reasoningEffort: 'low',
      );
      service.dispose();

      expect(reply, contains('water level 72.0%'));
      expect(reply, contains('temperature 27.4°C'));
      expect(requestCount, 2);
    },
  );

  test('cancellation stops the agent before another tool round', () async {
    var requestCount = 0;
    var cancelled = false;
    var toolCount = 0;
    final service = GroqCygnusService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'status-call',
                      'function': {
                        'name': 'get_current_status',
                        'arguments': '{}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      service.runAgent(
        systemInstruction: 'Test instruction',
        conversation: [
          CygnusMessage(
            id: 'user-1',
            role: 'user',
            text: 'Check status',
            createdAt: DateTime.now(),
          ),
        ],
        tools: const [],
        executeTool: (name, arguments) async {
          toolCount++;
          cancelled = true;
          return {'ok': true};
        },
        model: GroqCygnusService.fastModel,
        reasoningEffort: 'low',
        isCancelled: () => cancelled,
      ),
      throwsA(isA<CygnusAgentCancelled>()),
    );
    service.dispose();

    expect(toolCount, 1);
    expect(requestCount, 1);
  });

  test(
    'clarification tool pauses the agent before any other tool runs',
    () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'clarify-call',
                      'function': {
                        'name': 'request_clarification',
                        'arguments': jsonEncode({
                          'question': 'Which date should I use?',
                        }),
                      },
                    },
                    {
                      'id': 'motor-call',
                      'function': {
                        'name': 'set_motor',
                        'arguments': jsonEncode({'motor': 1, 'state': true}),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GroqCygnusService(client: client);
      final executedTools = <String>[];

      final reply = await service.runAgent(
        systemInstruction: 'Test instruction',
        conversation: [
          CygnusMessage(
            id: 'user-1',
            role: 'user',
            text: 'Schedule the motor at 6 PM.',
            createdAt: DateTime.now(),
          ),
        ],
        tools: const [],
        executeTool: (name, arguments) async {
          executedTools.add(name);
          return {
            'ok': true,
            'awaitingClarification': true,
            'question': arguments['question'],
          };
        },
        model: GroqCygnusService.fastModel,
        reasoningEffort: 'low',
      );
      service.dispose();

      expect(reply, 'Which date should I use?');
      expect(executedTools, ['request_clarification']);
    },
  );
}
