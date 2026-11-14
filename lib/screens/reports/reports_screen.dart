import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/expense.dart';
import '../../domain/summary/earnings_summary.dart';
import '../../services/earnings_exporter.dart';
import '../../state/earnings_provider.dart';
import '../../widgets/common.dart';
import 'expense_sheet.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.week;
  EarningsReport? _report;
  List<Expense> _expenses = const [];
  bool _loading = true;
  int _loadToken = 0;
  String? _signature;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _range(ReportPeriod period) {
    final now = DateTime.now();
    return switch (period) {
      ReportPeriod.today => (Dates.startOfDay(now), Dates.endOfDay(now)),
      ReportPeriod.week => (Dates.startOfWeek(now), Dates.endOfWeek(now)),
      ReportPeriod.month => (Dates.startOfMonth(now), Dates.endOfMonth(now)),
    };
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _loading = true);
    final provider = context.read<EarningsProvider>();
    final range = _range(_period);
    final report = await provider.buildReport(_period);
    final expenses = await provider.expensesBetween(range.$1, range.$2);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _report = report;
      _expenses = expenses;
      _loading = false;
    });
  }

  void _syncWithProvider(EarningsProvider provider) {
    final signature =
        '${provider.recent.length}:${provider.today.recordedEarningsCents}:${provider.today.bookingCount}';
    if (_signature == null) {
      _signature = signature;
      return;
    }
    if (signature != _signature) {
      _signature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _export({required bool csv}) async {
    final range = _range(_period);
    final provider = context.read<EarningsProvider>();
    final transactions = await provider.history(
      start: range.$1,
      end: range.$2,
      limit: 5000,
    );
    if (!mounted) return;
    try {
      if (csv) {
        await EarningsExporter.shareCsv(
          transactions: transactions,
          expenses: _expenses,
        );
      } else {
        await EarningsExporter.shareJson(
          transactions: transactions,
          expenses: _expenses,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EarningsProvider>();
    _syncWithProvider(provider);
    final report = _report;
    final summary = report?.summary ?? EarningsSummary.empty;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            const Text(
              'Reports',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Understand where your income comes from',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final period in ReportPeriod.values) ...[
                    ChoiceChip(
                      label: Text(switch (period) {
                        ReportPeriod.today => 'Today',
                        ReportPeriod.week => 'This week',
                        ReportPeriod.month => 'This month',
                      }),
                      selected: _period == period,
                      onSelected: (_) {
                        setState(() => _period = period);
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _ReportHero(summary: summary),
              const SizedBox(height: 12),
              _BreakdownCard(summary: summary),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Daily earnings',
                      subtitle: 'Recorded earnings per day',
                      padding: EdgeInsets.only(bottom: 16),
                    ),
                    if (report == null || report.dailyTotals.isEmpty)
                      const SizedBox(
                        height: 80,
                        child: Center(
                          child: Text(
                            'No completed bookings in this period',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    else
                      _DailyBars(totals: report.dailyTotals),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PaymentCard(summary: summary),
              const SizedBox(height: 12),
              _ExpensesCard(
                totalCents: summary.expensesCents,
                breakdown: report?.expenseBreakdown ?? const {},
                expenses: _expenses,
                onAdd: () async {
                  final saved = await showAddExpense(context);
                  if (saved == true) await _load();
                },
                onDelete: (expense) async {
                  final id = expense.id;
                  if (id == null) return;
                  await provider.deleteExpense(id);
                  await _load();
                },
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Export',
                      subtitle: 'Share a copy of this period',
                      padding: EdgeInsets.only(bottom: 12),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _export(csv: true),
                            icon: const Icon(Icons.table_chart_outlined,
                                size: 18),
                            label: const Text('CSV'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _export(csv: false),
                            icon:
                                const Icon(Icons.data_object_outlined, size: 18),
                            label: const Text('JSON'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Exports are created locally and shared through Android. '
                      'They do not include screenshots or passenger details.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportHero extends StatelessWidget {
  const _ReportHero({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C2745), Color(0xFF0A1A2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECORDED EARNINGS',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Money.format(summary.recordedEarningsCents),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              height: 1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ReportStat(
                label: 'Net after expenses',
                value: Money.format(summary.netEarningsCents),
                color: summary.netEarningsCents >= 0
                    ? AppColors.green
                    : AppColors.red,
              ),
              const SizedBox(width: 20),
              _ReportStat(
                label: 'Bookings',
                value: '${summary.bookingCount}',
                color: AppColors.primary,
                alignEnd: true,
              ),
              const SizedBox(width: 20),
              _ReportStat(
                label: 'Tips',
                value: Money.format(summary.tipsCents),
                color: AppColors.gold,
                alignEnd: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          LabeledValue(
            label: 'Platform total earnings',
            value: Money.format(summary.platformEarningsCents),
          ),
          LabeledValue(
            label: 'Tips (not already included)',
            value: Money.format(summary.tipsCents),
          ),
          LabeledValue(
            label: 'Fare collected (not income)',
            value: Money.format(summary.fareCollectedCents),
          ),
          LabeledValue(
            label: 'Expenses',
            value: '- ${Money.format(summary.expensesCents)}',
          ),
          const Divider(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Estimated net',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                Money.format(summary.netEarningsCents),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: summary.netEarningsCents >= 0
                      ? AppColors.green
                      : AppColors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.totals});

  final List<DailyTotal> totals;

  @override
  Widget build(BuildContext context) {
    final maxCents = totals.fold<int>(
      0,
      (max, day) => day.earningsCents > max ? day.earningsCents : max,
    );
    final showLabelEvery = totals.length > 10 ? 5 : 1;
    final today = Dates.startOfDay(DateTime.now());

    return SizedBox(
      height: 128,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < totals.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      totals[i].earningsCents == 0
                          ? ''
                          : Money.formatCompact(
                              totals[i].earningsCents,
                              withSymbol: false,
                            ),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: maxCents == 0
                          ? 4
                          : 4 +
                              (76 *
                                  (totals[i].earningsCents / maxCents)
                                      .clamp(0.0, 1.0)),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: Dates.isSameDay(totals[i].day, today)
                              ? [AppColors.green, AppColors.primary]
                              : [
                                  AppColors.primaryDeep,
                                  AppColors.primary.withValues(alpha: 0.6),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      i % showLabelEvery == 0
                          ? '${totals[i].day.day}'
                          : '',
                      style: const TextStyle(
                        fontSize: 8,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final entries = summary.paymentBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Payment methods',
            subtitle: 'Share of recorded earnings',
            padding: EdgeInsets.only(bottom: 12),
          ),
          if (entries.isEmpty)
            const Text(
              'No payments recorded yet.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            )
          else
            for (final entry in entries) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${Money.format(entry.value)}  •  ${total == 0 ? 0 : ((entry.value / total) * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : entry.value / total,
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceSoft,
                ),
              ),
              const SizedBox(height: 11),
            ],
        ],
      ),
    );
  }
}

class _ExpensesCard extends StatelessWidget {
  const _ExpensesCard({
    required this.totalCents,
    required this.breakdown,
    required this.expenses,
    required this.onAdd,
    required this.onDelete,
  });

  final int totalCents;
  final Map<String, int> breakdown;
  final List<Expense> expenses;
  final Future<void> Function() onAdd;
  final Future<void> Function(Expense) onDelete;

  @override
  Widget build(BuildContext context) {
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Expenses',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                Money.format(totalCents),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onAdd,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceElevated,
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No expenses in this period.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      Money.format(entry.value),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            if (expenses.isNotEmpty) const Divider(height: 18),
            for (final expense in expenses.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.description?.isNotEmpty == true
                            ? expense.description!
                            : expense.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      Dates.dateOnly.format(expense.createdAt),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onDelete(expense),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
