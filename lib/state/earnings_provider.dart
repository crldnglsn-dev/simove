import 'package:flutter/foundation.dart';

import '../core/utils/date_utils.dart';
import '../data/models/booking_transaction.dart';
import '../data/models/expense.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/summary/earnings_summary.dart';

enum ReportPeriod { today, week, month }

class EarningsProvider extends ChangeNotifier {
  EarningsProvider({
    required TransactionRepository transactionRepository,
    required ExpenseRepository expenseRepository,
  })  : _transactions = transactionRepository,
        _expenses = expenseRepository;

  final TransactionRepository _transactions;
  final ExpenseRepository _expenses;

  bool _loading = false;
  EarningsSummary _today = EarningsSummary.empty;
  EarningsSummary _week = EarningsSummary.empty;
  EarningsSummary _month = EarningsSummary.empty;
  List<BookingTransaction> _recent = const [];
  List<Expense> _todayExpenses = const [];
  List<BookingTransaction> _pending = const [];
  String? _error;

  bool get loading => _loading;
  EarningsSummary get today => _today;
  EarningsSummary get week => _week;
  EarningsSummary get month => _month;
  List<BookingTransaction> get recent => _recent;
  List<Expense> get todayExpenses => _todayExpenses;
  List<BookingTransaction> get pending => _pending;
  String? get error => _error;

  Future<void> refresh() async {
    final now = DateTime.now();
    final dayStart = Dates.startOfDay(now);
    final dayEnd = Dates.endOfDay(now);
    final weekStart = Dates.startOfWeek(now);
    final weekEnd = Dates.endOfWeek(now);
    final monthStart = Dates.startOfMonth(now);
    final monthEnd = Dates.endOfMonth(now);

    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _transactions.between(dayStart, dayEnd),
        _transactions.between(weekStart, weekEnd),
        _transactions.between(monthStart, monthEnd),
        _transactions.recent(limit: 25),
        _expenses.between(monthStart, monthEnd),
      ]);
      final todayTx = results[0] as List<BookingTransaction>;
      final weekTx = results[1] as List<BookingTransaction>;
      final monthTx = results[2] as List<BookingTransaction>;
      final recent = results[3] as List<BookingTransaction>;
      final monthExpenses = results[4] as List<Expense>;

      List<Expense> filterExpenses(DateTime start, DateTime end) => monthExpenses
          .where((e) => !e.createdAt.isBefore(start) && !e.createdAt.isAfter(end))
          .toList();

      _today = EarningsSummary.from(
        transactions: todayTx,
        expenses: filterExpenses(dayStart, dayEnd),
      );
      _week = EarningsSummary.from(
        transactions: weekTx,
        expenses: filterExpenses(weekStart, weekEnd),
      );
      _month = EarningsSummary.from(
        transactions: monthTx,
        expenses: monthExpenses,
      );
      _recent = recent;
      _todayExpenses = filterExpenses(dayStart, dayEnd);
      _pending = recent.where((t) => t.bookingStatus.isPending).toList();
      _error = null;
    } catch (error) {
      _error = 'Could not load earnings: $error';
      debugPrint(_error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<BookingTransaction> addManual({
    required int platformEarningsCents,
    required int fareToCollectCents,
    required String paymentMethod,
    int tipCents = 0,
    TipType tipType = TipType.cash,
    bool tipIncluded = false,
    String? notes,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    final created = createdAt ?? now;
    final pending = await _transactions.createPending(
      source: DetectionSource.manual,
      createdAt: created,
    );
    final completed = await _transactions.update(
      pending.copyWith(
        bookingStatus: BookingState.recorded,
        updatedAt: now,
        platformEarningsCents: platformEarningsCents,
        fareToCollectCents: fareToCollectCents,
        paymentMethod: paymentMethod,
        tipCents: tipCents,
        tipType: tipType,
        tipIncludedInPlatformEarnings: tipIncluded,
        notes: notes,
        earningsDetectedAt: created,
        isManuallyEdited: true,
      ),
    );
    await refresh();
    return completed;
  }

  Future<BookingTransaction> updateTransaction(
    BookingTransaction transaction, {
    bool markEdited = true,
  }) async {
    final updated = await _transactions.update(
      transaction.copyWith(
        isManuallyEdited: markEdited ? true : transaction.isManuallyEdited,
      ),
    );
    await refresh();
    return updated;
  }

  Future<void> setTip(
    BookingTransaction transaction, {
    required int tipCents,
    required TipType tipType,
    required bool included,
  }) async {
    await updateTransaction(
      transaction.copyWith(
        tipCents: tipCents,
        tipType: tipType,
        tipIncludedInPlatformEarnings: included,
      ),
    );
  }

  Future<void> deleteTransaction(int id) async {
    await _transactions.delete(id);
    await refresh();
  }

  Future<void> addExpense({
    required String category,
    required int amountCents,
    String? description,
    DateTime? createdAt,
  }) async {
    await _expenses.insert(
      Expense(
        category: category,
        amountCents: amountCents,
        description: description,
        createdAt: createdAt ?? DateTime.now(),
      ),
    );
    await refresh();
  }

  Future<void> deleteExpense(int id) async {
    await _expenses.delete(id);
    await refresh();
  }

  Future<BookingTransaction?> getById(int id) => _transactions.getById(id);

  Future<List<Expense>> expensesBetween(DateTime start, DateTime end) =>
      _expenses.between(start, end);

  Future<EarningsReport> buildReport(ReportPeriod period) async {
    final now = DateTime.now();
    final (start, end) = switch (period) {
      ReportPeriod.today => (Dates.startOfDay(now), Dates.endOfDay(now)),
      ReportPeriod.week => (Dates.startOfWeek(now), Dates.endOfWeek(now)),
      ReportPeriod.month => (Dates.startOfMonth(now), Dates.endOfMonth(now)),
    };
    final transactions = await _transactions.between(start, end);
    final expenses = await _expenses.between(start, end);
    return EarningsCalculator.buildReport(
      start: start,
      end: end,
      transactions: transactions,
      expenses: expenses,
    );
  }

  Future<List<BookingTransaction>> history({
    DateTime? start,
    DateTime? end,
    int limit = 500,
  }) async {
    if (start == null || end == null) {
      return _transactions.recent(limit: limit);
    }
    return _transactions.between(start, end, limit: limit);
  }

  Future<void> clearAll() async {
    await _transactions.deleteAll();
    await _expenses.deleteAll();
    await refresh();
  }
}
