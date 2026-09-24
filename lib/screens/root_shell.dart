import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../core/app_theme.dart';
import 'control_page.dart';
import 'history_page.dart';
import 'live_page.dart';
import 'monitor_page.dart';
import 'system_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;

  static const _pages = <Widget>[
    LivePage(),
    ControlPage(),
    MonitorPage(),
    HistoryPage(),
    SystemPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AgroController>().initialize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AgroController>().onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Selector<AgroController, String?>(
              selector: (_, controller) => controller.error,
              builder: (context, error, _) {
                if (error == null || error.isEmpty) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.red.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 19),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(color: AppTheme.red, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: context.read<AgroController>().clearError,
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.red),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.stream_rounded), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Control'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Monitor'),
          NavigationDestination(icon: Icon(Icons.show_chart_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'System'),
        ],
      ),
    );
  }
}
