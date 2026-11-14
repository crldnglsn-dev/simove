import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'data/repositories/expense_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'state/earnings_provider.dart';
import 'state/monitoring_provider.dart';
import 'state/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    final database = AppDatabase();
    await database.open();

    final settingsRepository = SettingsRepository(database);
    final transactionRepository = TransactionRepository(database);
    final expenseRepository = ExpenseRepository(database);

    final settings = SettingsProvider(settingsRepository);
    await settings.load();

    final earnings = EarningsProvider(
      transactionRepository: transactionRepository,
      expenseRepository: expenseRepository,
    );
    await earnings.refresh();

    final monitoring = MonitoringProvider(
      transactionRepository: transactionRepository,
      settings: settings,
      earnings: earnings,
    );
    await monitoring.init();

    runApp(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: database),
          Provider<TransactionRepository>.value(value: transactionRepository),
          Provider<ExpenseRepository>.value(value: expenseRepository),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<EarningsProvider>.value(value: earnings),
          ChangeNotifierProvider<MonitoringProvider>.value(value: monitoring),
        ],
        child: const SimoveApp(),
      ),
    );
  } catch (error) {
    runApp(StartupErrorApp(error: error.toString()));
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.red, size: 42),
                const SizedBox(height: 18),
                const Text(
                  'SIMOVE could not start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The local database or Android services failed to initialise. '
                  'Your saved transactions are stored on this device and were not deleted.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  error,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
