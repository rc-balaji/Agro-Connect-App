import 'package:agro_connect/controllers/cygnus_controller.dart';
import 'package:agro_connect/core/app_theme.dart';
import 'package:agro_connect/cygnus/cygnus_models.dart';
import 'package:agro_connect/screens/cygnus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class PreviewController extends CygnusController {
  @override
  bool get voiceAvailable => true;
  @override
  bool get busy => true;
  @override
  String get status => 'Reading farm data…';
  @override
  List<CygnusMessage> get messages => [
    CygnusMessage(
      id: '1',
      role: 'assistant',
      text: 'Hi! Ask me about your farm.',
      createdAt: DateTime(2026),
    ),
    CygnusMessage(
      id: '2',
      role: 'user',
      text: 'Current temperature enna?',
      createdAt: DateTime(2026),
    ),
  ];
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('chat fits $width wide and retains drafts while waiting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PreviewController();
      await tester.pumpWidget(
        ChangeNotifierProvider<CygnusController>.value(
          value: controller,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: CygnusPage(onNavigate: (_) {})),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Saved on this phone'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Next question');
      expect(find.text('Next question'), findsOneWidget);
      final send = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Send',
        ),
      );
      expect(send.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
