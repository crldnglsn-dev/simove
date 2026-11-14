import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:simove/app.dart';
import 'package:simove/data/database/app_database.dart';
import 'package:simove/data/repositories/expense_repository.dart';
import 'package:simove/data/repositories/settings_repository.dart';
import 'package:simove/data/repositories/transaction_repository.dart';
import 'package:simove/services/monitoring_platform.dart';
import 'package:simove/state/earnings_provider.dart';
import 'package:simove/state/monitoring_provider.dart';
import 'package:simove/state/settings_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeMonitoringPlatform extends MonitoringPlatform {
  @override
  Stream<MonitoringEvent> get events => const Stream.empty();

  @override
  Future<PermissionSnapshot> getPermissionStatus() async =>
      const PermissionSnapshot(sdkInt: 34);

  @override
  Future<Map<Object?, Object?>?> getLastOcr() async => null;

  @override
  Future<bool> isCaptureRunning() async => false;

  @override
  Future<void> setTargetPackage(String packageName) async {}
}

/// Pumps the UI while allowing real SQLite futures (sqflite FFI) to complete.
/// `pumpAndSettle` alone can spin forever on progress indicators that wait for
/// real file I/O.
Future<void> pumpUi(WidgetTester tester, {int iterations = 14}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app shell renders, onboards and shows recorded earnings',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final databaseName =
        'simove_widget_${DateTime.now().microsecondsSinceEpoch}.db';
    late final AppDatabase database;
    late final SettingsProvider settings;
    late final EarningsProvider earnings;
    late final MonitoringProvider monitoring;

    await tester.runAsync(() async {
      database = AppDatabase(databaseName: databaseName);
      await database.open();
      final transactions = TransactionRepository(database);
      final expenses = ExpenseRepository(database);
      settings = SettingsProvider(SettingsRepository(database));
      await settings.load();
      earnings = EarningsProvider(
        transactionRepository: transactions,
        expenseRepository: expenses,
      );
      await earnings.refresh();
      monitoring = MonitoringProvider(
        transactionRepository: transactions,
        settings: settings,
        earnings: earnings,
        platform: FakeMonitoringPlatform(),
      );
      await monitoring.init();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<EarningsProvider>.value(value: earnings),
          ChangeNotifierProvider<MonitoringProvider>.value(value: monitoring),
        ],
        child: const SimoveApp(),
      ),
    );
    await pumpUi(tester);

    // First run offers monitoring setup once.
    expect(find.text('Set up automatic detection'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await pumpUi(tester);

    expect(find.text('SIMOVE'), findsOneWidget);
    expect(find.text("TODAY'S EARNINGS"), findsOneWidget);

    // A recorded booking reaches the dashboard.
    await tester.runAsync(
      () => earnings.addManual(
        platformEarningsCents: 7500,
        fareToCollectCents: 9500,
        paymentMethod: 'Cash',
      ),
    );
    await pumpUi(tester);
    expect(find.text('₱75.00'), findsWidgets);
    expect(find.textContaining('₱95.00'), findsWidgets);
    expect(find.text('No bookings yet'), findsNothing);

    // Tabs render their own content.
    await tester.tap(find.text('Transactions'));
    await pumpUi(tester);
    expect(find.text('Every booking, tip and fare in one place'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await pumpUi(tester);
    expect(find.text('Understand where your income comes from'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await pumpUi(tester);
    expect(
      find.text('Control monitoring, privacy and local data'),
      findsOneWidget,
    );

    // Editing the monitored package must not crash while the dialog closes.
    await tester.tap(find.text('Angkas app package'));
    await pumpUi(tester);
    expect(find.text('Android package name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'com.android.chrome');
    await tester.tap(find.text('Save'));
    await pumpUi(tester);
    expect(
      find.text('Monitoring target set to com.android.chrome'),
      findsOneWidget,
    );

    // Remove the widget tree before closing the database.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await database.close();
      final path = p.join(await getDatabasesPath(), databaseName);
      await databaseFactory.deleteDatabase(path);
    });
  });
}
