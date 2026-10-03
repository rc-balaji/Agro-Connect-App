import 'dart:convert';

import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:agro_connect/cygnus/groq_cygnus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
