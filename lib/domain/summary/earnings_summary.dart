import '../../core/utils/date_utils.dart';
import '../../data/models/booking_transaction.dart';
import '../../data/models/expense.dart';

/// Aggregated earnings for a date range.
class EarningsSummary {
  const EarningsSummary({
    required this.platformEarningsCents,
    required this.tipsCents,
    required this.recordedEarningsCents,
    required this.fareCollectedCents,
    required this.expensesCents,
    required this.bookingCount,
    required this.pendingCount,
    required this.paymentBreakdown,
  });

  final int platformEarningsCents;
  final int tipsCents;
  final int recordedEarningsCents;
  final int fareCollectedCents;
  final int expensesCents;
  final int bookingCount;
  final int pendingCount;
  final Map<String, int> paymentBreakdown;

  int get netEarningsCents => recordedEarningsCents - expensesCents;

  static const empty = EarningsSummary(
    platformEarningsCents: 0,
    tipsCents: 0,
    recordedEarningsCents: 0,
    fareCollectedCents: 0,
    expensesCents: 0,
    bookingCount: 0,
    pendingCount: 0,
    paymentBreakdown: {},
  );

  factory EarningsSummary.from({
    required Iterable<BookingTransaction> transactions,
    Iterable<Expense> expenses = const [],
    bool includePendingCount = true,
  }) {
    var platform = 0;
    var tips = 0;
    var fare = 0;
    var count = 0;
    var pending = 0;
    final payments = <String, int>{};

    for (final transaction in transactions) {
      if (includePendingCount && transaction.hasPlatformEarnings == false) {
        pending++;
      }
      if (!transaction.hasPlatformEarnings) continue;
      count++;
      platform += transaction.platformEarningsCents ?? 0;
      tips += transaction.effectiveTipCents;
      fare += transaction.fareToCollectCents ?? 0;
      final method = transaction.paymentMethod?.trim();
      final key = (method == null || method.isEmpty) ? 'Unspecified' : method;
      payments[key] = (payments[key] ?? 0) + transaction.recordedEarningsCents;
    }

    final expenseTotal = expenses.fold<int>(0, (sum, e) => sum + e.amountCents);

    return EarningsSummary(
      platformEarningsCents: platform,
      tipsCents: tips,
      recordedEarningsCents: platform + tips,
      fareCollectedCents: fare,
      expensesCents: expenseTotal,
      bookingCount: count,
      pendingCount: pending,
      paymentBreakdown: payments,
    );
  }
}

class DailyTotal {
  const DailyTotal({
    required this.day,
    required this.earningsCents,
    required this.bookingCount,
  });

  final DateTime day;
  final int earningsCents;
  final int bookingCount;
}

class EarningsReport {
  const EarningsReport({
    required this.summary,
    required this.dailyTotals,
    required this.expenseBreakdown,
    required this.transactionCount,
  });

  final EarningsSummary summary;
  final List<DailyTotal> dailyTotals;
  final Map<String, int> expenseBreakdown;
  final int transactionCount;
}

class EarningsCalculator {
  EarningsCalculator._();

  /// Builds a report for [start]..[end], including a daily series where every
  /// day in the range is present (zeroes included) for stable charts.
  static EarningsReport buildReport({
    required DateTime start,
    required DateTime end,
    required List<BookingTransaction> transactions,
    required List<Expense> expenses,
  }) {
    final summary = EarningsSummary.from(
      transactions: transactions,
      expenses: expenses,
    );

    final buckets = <DateTime, List<BookingTransaction>>{};
    var cursor = Dates.startOfDay(start);
    final lastDay = Dates.startOfDay(end);
    while (!cursor.isAfter(lastDay)) {
      buckets[cursor] = [];
      cursor = cursor.add(const Duration(days: 1));
    }
    for (final transaction in transactions) {
      if (!transaction.hasPlatformEarnings) continue;
      final day = Dates.startOfDay(transaction.createdAt);
      buckets.putIfAbsent(day, () => []).add(transaction);
    }
    final daily = buckets.entries
        .map((entry) {
          final total = entry.value.fold<int>(
            0,
            (sum, t) => sum + t.recordedEarningsCents,
          );
          return DailyTotal(
            day: entry.key,
            earningsCents: total,
            bookingCount: entry.value.length,
          );
        })
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));

    final expenseBreakdown = <String, int>{};
    for (final expense in expenses) {
      expenseBreakdown[expense.category] =
          (expenseBreakdown[expense.category] ?? 0) + expense.amountCents;
    }

    return EarningsReport(
      summary: summary,
      dailyTotals: daily,
      expenseBreakdown: expenseBreakdown,
      transactionCount: transactions.length,
    );
  }
}
