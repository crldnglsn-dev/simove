import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/setup/monitoring_setup_sheet.dart';
import 'screens/transactions/transactions_screen.dart';
import 'state/monitoring_provider.dart';
import 'state/settings_provider.dart';

class SimoveApp extends StatelessWidget {
  const SimoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIMOVE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const SimoveShell(),
    );
  }
}

class SimoveShell extends StatefulWidget {
  const SimoveShell({super.key});

  @override
  State<SimoveShell> createState() => _SimoveShellState();
}

class _SimoveShellState extends State<SimoveShell> {
  int _index = 0;
  bool _offeredSetup = false;
  bool _autoStartAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final monitoring = context.read<MonitoringProvider>();
    if (!settings.onboardingCompleted && !_offeredSetup) {
      _offeredSetup = true;
      await showMonitoringSetup(context, firstRun: true);
    }
    if (!mounted || _autoStartAttempted) return;
    _autoStartAttempted = true;
    if (settings.autoMonitoring && !monitoring.isMonitoring) {
      await monitoring.startMonitoring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        onViewAllTransactions: () => setState(() => _index = 1),
        onOpenSettings: () => setState(() => _index = 3),
      ),
      const TransactionsScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
