import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:simove/data/database/app_database.dart';
import 'package:simove/data/models/booking_transaction.dart';
import 'package:simove/data/models/expense.dart';
import 'package:simove/data/repositories/expense_repository.dart';
import 'package:simove/data/repositories/settings_repository.dart';
import 'package:simove/data/repositories/transaction_repository.dart';
import 'package:simove/domain/summary/earnings_summary.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String databaseName;

  setUp(() {
    databaseName = 'simove_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  Future<void> deleteDatabaseFile() async {
    final path = p.join(await getDatabasesPath(), databaseName);
    await databaseFactory.deleteDatabase(path);
  }

  test('Test 9: a pending booking survives an application restart', () async {
    final first = AppDatabase(databaseName: databaseName);
    await first.open();
    final repository = TransactionRepository(first);
    final created = await repository.createPending(
      signature: 'signature-1',
      confidence: 0.72,
    );
    expect(created.bookingReference, startsWith('SMV-'));

    // Simulates the process being killed and the app being reopened.
    await first.close();

    final second = AppDatabase(databaseName: databaseName);
    await second.open();
    final reopened = TransactionRepository(second);
    final active = await reopened.latestActive();

    expect(active, isNotNull);
    expect(active!.id, created.id);
    expect(active.bookingReference, created.bookingReference);
    expect(active.bookingStatus, BookingState.bookingDetected);
    expect(active.platformEarningsCents, isNull);
    expect(active.bookingReference, matches(RegExp(r'^SMV-\d{8}-\d{3}$')));

    await second.close();
    await deleteDatabaseFile();
  });

  test('an ended booking is not returned as the active record', () async {
    final database = AppDatabase(databaseName: databaseName);
    await database.open();
    final repository = TransactionRepository(database);

    final first = await repository.createPending();
    await repository.update(
      first.copyWith(
        bookingStatus: BookingState.bookingEnded,
        endedAt: DateTime.now(),
        platformEarningsCents: 7500,
        fareToCollectCents: 9500,
        paymentMethod: 'Cash',
      ),
    );

    expect(await repository.latestActive(), isNull);

    final second = await repository.createPending();
    final active = await repository.latestActive();
    expect(active!.id, second.id);
    expect(active.id, isNot(first.id));

    await database.close();
    await deleteDatabaseFile();
  });

  test('booking references are unique per day even after deletions', () async {
    final database = AppDatabase(databaseName: databaseName);
    await database.open();
    final repository = TransactionRepository(database);
    final day = DateTime(2026, 11, 14, 9);

    final first = await repository.createPending(createdAt: day);
    expect(first.bookingReference, 'SMV-20261114-001');
    final second = await repository.createPending(createdAt: day);
    expect(second.bookingReference, 'SMV-20261114-002');

    await repository.delete(first.id!);
    final third = await repository.createPending(createdAt: day);
    expect(third.bookingReference, isNot(first.bookingReference));
    expect(await repository.referenceExists(third.bookingReference), isTrue);

    await database.close();
    await deleteDatabaseFile();
  });

  test('tips and settings round-trip through sqlite', () async {
    final database = AppDatabase(databaseName: databaseName);
    await database.open();
    final repository = TransactionRepository(database);
    final settings = SettingsRepository(database);
    final expenses = ExpenseRepository(database);

    final pending = await repository.createPending();
    final completed = await repository.update(
      pending.copyWith(
        bookingStatus: BookingState.recorded,
        platformEarningsCents: 7500,
        fareToCollectCents: 9500,
        paymentMethod: 'Cash',
        tipCents: 2000,
        tipType: TipType.digital,
        tipIncludedInPlatformEarnings: false,
        isManuallyEdited: true,
      ),
    );
    expect(completed.recordedEarningsCents, 9500);

    await expenses.insert(
      Expense(
        category: ExpenseCategory.gasoline,
        amountCents: 30000,
        createdAt: DateTime(2026, 11, 14),
      ),
    );
    await settings.put('display.currency', 'PHP');

    await database.close();

    final reopened = AppDatabase(databaseName: databaseName);
    await reopened.open();
    final reloaded = await TransactionRepository(reopened).getById(pending.id!);
    expect(reloaded!.tipCents, 2000);
    expect(reloaded.tipType, TipType.digital);
    expect(reloaded.isManuallyEdited, isTrue);
    expect(reloaded.recordedEarningsCents, 9500);

    final values = await SettingsRepository(reopened).loadAll();
    expect(values['display.currency'], 'PHP');
    final storedExpenses = await ExpenseRepository(reopened)
        .between(DateTime(2026, 11, 14), DateTime(2026, 11, 15));
    expect(storedExpenses, hasLength(1));
    expect(storedExpenses.first.amountCents, 30000);

    await reopened.close();
    await deleteDatabaseFile();
  });

  test('Test 10: daily summary adds platform earnings and tips only once', () {
    final day = DateTime(2026, 11, 14);
    final transactions = [
      BookingTransaction(
        bookingReference: 'SMV-20261114-001',
        bookingStatus: BookingState.recorded,
        createdAt: day.add(const Duration(hours: 8)),
        updatedAt: day.add(const Duration(hours: 8)),
        platformEarningsCents: 7500,
        fareToCollectCents: 9500,
        paymentMethod: 'Cash',
        tipCents: 2000,
        tipType: TipType.cash,
      ),
      BookingTransaction(
        bookingReference: 'SMV-20261114-002',
        bookingStatus: BookingState.recorded,
        createdAt: day.add(const Duration(hours: 9)),
        updatedAt: day.add(const Duration(hours: 9)),
        platformEarningsCents: 10000,
        fareToCollectCents: 13000,
        paymentMethod: 'GCash',
        tipCents: 5000,
        tipType: TipType.digital,
        tipIncludedInPlatformEarnings: true,
      ),
      BookingTransaction(
        bookingReference: 'SMV-20261114-003',
        bookingStatus: BookingState.recorded,
        createdAt: day.add(const Duration(hours: 10)),
        updatedAt: day.add(const Duration(hours: 10)),
        platformEarningsCents: 6000,
        fareToCollectCents: 8000,
        paymentMethod: 'Cash',
      ),
      BookingTransaction(
        bookingReference: 'SMV-20261114-004',
        bookingStatus: BookingState.waitingForEarnings,
        createdAt: day.add(const Duration(hours: 11)),
        updatedAt: day.add(const Duration(hours: 11)),
      ),
    ];
    final expenses = [
      Expense(
        category: ExpenseCategory.gasoline,
        amountCents: 15000,
        createdAt: day.add(const Duration(hours: 7)),
      ),
      Expense(
        category: ExpenseCategory.parking,
        amountCents: 5000,
        createdAt: day.add(const Duration(hours: 12)),
      ),
    ];

    final report = EarningsCalculator.buildReport(
      start: day,
      end: day.add(const Duration(hours: 23, minutes: 59)),
      transactions: transactions,
      expenses: expenses,
    );

    final summary = report.summary;
    // 75 + 100 + 60 platform earnings.
    expect(summary.platformEarningsCents, 23500);
    // Only the first tip is additional; the second is already included.
    expect(summary.tipsCents, 2000);
    expect(summary.recordedEarningsCents, 25500);
    // The fare the rider collects is not income.
    expect(summary.fareCollectedCents, 30500);
    expect(summary.bookingCount, 3);
    expect(summary.pendingCount, 1);
    expect(summary.expensesCents, 20000);
    expect(summary.netEarningsCents, 5500);
    expect(summary.paymentBreakdown['Cash'], 15500);
    expect(summary.paymentBreakdown['GCash'], 10000);
    expect(report.dailyTotals, hasLength(1));
    expect(report.dailyTotals.first.earningsCents, 25500);
    expect(report.dailyTotals.first.bookingCount, 3);
    expect(report.expenseBreakdown[ExpenseCategory.gasoline], 15000);
  });
}
