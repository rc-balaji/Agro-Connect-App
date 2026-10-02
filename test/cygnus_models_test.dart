import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CygnusMessage round trips through JSON', () {
    final message = CygnusMessage(
      id: 'm1',
      role: 'assistant',
      text: 'Motor 2 started.',
      kind: 'text',
      payload: const <String, dynamic>{'motor': 2, 'state': true},
      createdAt: DateTime.fromMillisecondsSinceEpoch(123456789),
    );

    final decoded = CygnusMessage.decode(message.encode());
    expect(decoded.id, 'm1');
    expect(decoded.role, 'assistant');
    expect(decoded.text, 'Motor 2 started.');
    expect(decoded.payload['motor'], 2);
    expect(decoded.payload['state'], true);
    expect(decoded.createdAt.millisecondsSinceEpoch, 123456789);
  });

  test('Cygnus session summary reads persisted metadata', () {
    final summary = CygnusSessionSummary.fromMap('chat_1', <String, dynamic>{
      'title': 'Morning plan',
      'languageCode': 'ta',
      'updatedAt': 1000,
    });

    expect(summary.id, 'chat_1');
    expect(summary.title, 'Morning plan');
    expect(summary.languageCode, 'ta');
    expect(summary.updatedAt.millisecondsSinceEpoch, 1000);
  });
}
