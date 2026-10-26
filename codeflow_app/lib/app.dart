import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'models/project.dart';
import 'features/automation/automation_screen.dart';
import 'features/file_tree/file_selector_screen.dart';
import 'features/home/home_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/screen_monitor/screen_monitor_screen.dart';
import 'features/settings/settings_screen.dart';

class CodeFlowApp extends ConsumerWidget {
  const CodeFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'CodeFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _currentIndex = 0;

  void _onOpenProject(Project project) {
    ref.read(selectedProjectProvider.notifier).state = project;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => FileSelectorScreen(
          project: project,
          onProceedToAutomation: () {
            Navigator.of(ctx).pop();
            setState(() => _currentIndex = 2); // Switch to Automation tab
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(
        onNavigateTab: (idx) => setState(() => _currentIndex = idx),
        onOpenProject: _onOpenProject,
      ),
      ProjectsScreen(
        onSelectProject: _onOpenProject,
      ),
      const AutomationScreen(),
      const ScreenMonitorScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Projects',
            ),
            NavigationDestination(
              icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle),
              label: 'Automate',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_outlined),
              selectedIcon: Icon(Icons.monitor),
              label: 'Monitor',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
