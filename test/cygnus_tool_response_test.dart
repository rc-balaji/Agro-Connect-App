import 'dart:convert';

import 'package:agro_connect/controllers/cygnus_controller.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tool replies use user role and preserve results, call IDs and order',
    () {
      final content = CygnusController.createToolResponseMessage(
        const <FunctionResponse>[
          FunctionResponse('get_current_status', <String, Object?>{
            'ok': true,
            'dataStatus': 'current',
            'temperatureC': 28.5,
          }, id: 'status-call-1'),
          FunctionResponse('get_current_context', <String, Object?>{
            'ok': true,
            'timezone': 'Asia/Kolkata',
          }, id: 'context-call-2'),
        ],
      );

      final wire =
          jsonDecode(jsonEncode(content.toJson())) as Map<String, dynamic>;
      expect(wire['role'], 'user');
      expect(wire['parts'], <Map<String, Object?>>[
        <String, Object?>{
          'functionResponse': <String, Object?>{
            'name': 'get_current_status',
            'response': <String, Object?>{
              'ok': true,
              'dataStatus': 'current',
              'temperatureC': 28.5,
            },
            'id': 'status-call-1',
          },
        },
        <String, Object?>{
          'functionResponse': <String, Object?>{
            'name': 'get_current_context',
            'response': <String, Object?>{
              'ok': true,
              'timezone': 'Asia/Kolkata',
            },
            'id': 'context-call-2',
          },
        },
      ]);
    },
  );

  test('tool calls without an ID remain valid user-role responses', () {
    final content = CygnusController.createToolResponseMessage(
      const <FunctionResponse>[
        FunctionResponse('get_current_status', <String, Object?>{'ok': false}),
      ],
    );
    final wire = content.toJson();
    final part = (wire['parts'] as List).single as Map;
    final response = part['functionResponse'] as Map;
    expect(wire['role'], 'user');
    expect(response.containsKey('id'), isFalse);
    expect(response['response'], <String, Object?>{'ok': false});
  });
}
