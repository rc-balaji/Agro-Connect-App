import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'controllers/agro_controller.dart';
import 'controllers/cygnus_controller.dart';
import 'controllers/foreground_monitor_controller.dart';
import 'controllers/plan_controller.dart';
import 'core/app_theme.dart';
import 'core/firebase_bootstrap.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Firebase is additive to the farm controls. If Firebase/App Check is not
  // ready yet, FirebaseBootstrap records the warning and the rest of the app
  // continues to work normally.
  await FirebaseBootstrap.initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF091913),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AgroController()),
        ChangeNotifierProvider(create: (_) => PlanController()),
        ChangeNotifierProvider(create: (_) => ForegroundMonitorController()),
        ChangeNotifierProxyProvider2<AgroController, PlanController,
            CygnusController>(
          create: (_) => CygnusController(),
          update: (_, agro, plans, cygnus) {
            final controller = cygnus ?? CygnusController();
            controller.attach(agro, plans);
            return controller;
          },
        ),
      ],
      child: const AgroConnectApp(),
    ),
  );
}

class AgroConnectApp extends StatelessWidget {
  const AgroConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGRO CONNECT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const SplashScreen(),
    );
  }
}
