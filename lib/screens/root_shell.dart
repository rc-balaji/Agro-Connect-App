import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agro_controller.dart';
import '../controllers/plan_controller.dart';
import '../core/app_theme.dart';
import 'control_page.dart';
import 'history_page.dart';
import 'leaf_ai_page.dart';
import 'live_page.dart';
import 'monitor_page.dart';
import 'plan_page.dart';
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
    PlanPage(),
    MonitorPage(),
    HistoryPage(),
    LeafAiPage(),
    SystemPage(),
  ];

  static const _labels = [
    'Home',
    'Motors',
    'Plans',
    'Monitor',
    'History',
    'Plant Health',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AgroController>().initialize();
      context.read<PlanController>().initialize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AgroController>().onAppResumed();
      context.read<PlanController>().refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _selectPage(int value) {
    Navigator.of(context).maybePop();
    if (_index != value) setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _AgroDrawer(
        selectedIndex: _index,
        onSelectPage: _selectPage,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Builder(
              builder: (context) => _ShellHeader(
                title: _labels[_index],
                onMenu: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            Selector<AgroController, String?>(
              selector: (_, controller) => controller.error,
              builder: (context, error, _) {
                if (error == null || error.isEmpty) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                          style: const TextStyle(
                            color: AppTheme.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
              child: IndexedStack(index: _index, children: _pages),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.title, required this.onMenu});

  final String title;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF081A13),
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.7)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
          ),
          const SizedBox(width: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/branding/app_icon.png',
              width: 32,
              height: 32,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AGRO CONNECT',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    fontSize: 14,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Selector<AgroController, bool>(
            selector: (_, c) => c.deviceOnline,
            builder: (_, online, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: (online ? AppTheme.emerald : AppTheme.red).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: (online ? AppTheme.emerald : AppTheme.red).withValues(alpha: 0.22),
                ),
              ),
              child: Text(
                online ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: online ? AppTheme.emeraldSoft : AppTheme.red,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgroDrawer extends StatelessWidget {
  const _AgroDrawer({
    required this.selectedIndex,
    required this.onSelectPage,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    const items = <({IconData icon, String label})>[
      (icon: Icons.home_rounded, label: 'Home'),
      (icon: Icons.tune_rounded, label: 'Motors'),
      (icon: Icons.calendar_month_rounded, label: 'Plans'),
      (icon: Icons.monitor_heart_outlined, label: 'Monitor'),
      (icon: Icons.show_chart_rounded, label: 'History'),
      (icon: Icons.eco_rounded, label: 'Plant Health'),
      (icon: Icons.settings_outlined, label: 'Settings'),
    ];

    return Drawer(
      backgroundColor: const Color(0xFF081A13),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      width: 48,
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AGRO CONNECT',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'SMART FARMING',
                          style: TextStyle(
                            color: AppTheme.muted,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = selectedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: AppTheme.emerald.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(
                        item.icon,
                        color: selected ? AppTheme.emerald : AppTheme.muted,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.emeraldSoft,
                              size: 20,
                            )
                          : null,
                      onTap: () => onSelectPage(index),
                    ),
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Text(
                'Smart farming, simply connected',
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
