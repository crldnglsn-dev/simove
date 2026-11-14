import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import 'tip_sheet.dart';
import 'transaction_detail_sheet.dart';
import 'transaction_form_sheet.dart';

enum _HistoryFilter { all, today, week, month }

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();
  _HistoryFilter _filter = _HistoryFilter.today;
  List<BookingTransaction> _items = const [];
  bool _loading = true;
  String? _signature;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  (DateTime, DateTime)? get _range {
    final now = DateTime.now();
    return switch (_filter) {
      _HistoryFilter.all => null,
      _HistoryFilter.today => (Dates.startOfDay(now), Dates.endOfDay(now)),
      _HistoryFilter.week => (Dates.startOfWeek(now), Dates.endOfWeek(now)),
      _HistoryFilter.month => (Dates.startOfMonth(now), Dates.endOfMonth(now)),
    };
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final range = _range;
    final items = await context.read<EarningsProvider>().history(
          start: range?.$1,
          end: range?.$2,
        );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _syncWithProvider(EarningsProvider provider) {
    final signature =
        '${provider.recent.length}:${provider.today.recordedEarningsCents}:${provider.today.bookingCount}:${provider.pending.length}';
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

  List<BookingTransaction> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((t) {
      return t.bookingReference.toLowerCase().contains(query) ||
          (t.paymentMethod ?? '').toLowerCase().contains(query) ||
          (t.notes ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EarningsProvider>();
    _syncWithProvider(provider);
    final items = _filtered;

    return SafeArea(
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transactions',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Every booking, tip and fare in one place',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final saved = await TransactionFormSheet.show(context);
                        if (saved == true) await _load();
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                      ),
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search reference, payment or notes',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _HistoryFilter.values) ...[
                        ChoiceChip(
                          label: Text(switch (filter) {
                            _HistoryFilter.all => 'All',
                            _HistoryFilter.today => 'Today',
                            _HistoryFilter.week => 'This week',
                            _HistoryFilter.month => 'This month',
                          }),
                          selected: _filter == filter,
                          onSelected: (_) {
                            setState(() => _filter = filter);
                            _load();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (items.isEmpty)
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: _search.text.isEmpty
                          ? 'No transactions in this period'
                          : 'No matches found',
                      message: _search.text.isEmpty
                          ? 'Bookings detected automatically and manual entries will appear here.'
                          : 'Try a different reference or payment method.',
                      actionLabel:
                          _search.text.isEmpty ? 'Add manually' : null,
                      onAction: () => TransactionFormSheet.show(context),
                    ),
                  )
                else
                  ...[
                    _SummaryStrip(items: items),
                    const SizedBox(height: 14),
                    ..._buildRows(items),
                  ],
              ],
            ),
          ),
          Positioned(
            right: 18,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () async {
                final saved = await TransactionFormSheet.show(context);
                if (saved == true) await _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRows(List<BookingTransaction> items) {
    final groups = <DateTime, List<BookingTransaction>>{};
    for (final item in items) {
      final day = Dates.startOfDay(item.createdAt);
      groups.putIfAbsent(day, () => []).add(item);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final widgets = <Widget>[];
    for (final day in days) {
      final dayItems = groups[day]!;
      final dayTotal = dayItems.fold<int>(
        0,
        (sum, t) => sum + (t.hasPlatformEarnings ? t.recordedEarningsCents : 0),
      );
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 6),
          child: Row(
            children: [
              Text(
                Dates.relativeLabel(day),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                Money.format(dayTotal),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ),
      );
      for (final transaction in dayItems) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TransactionTile(
              transaction: transaction,
              showDay: false,
              onTap: () async {
                await TransactionDetailSheet.show(
                  context,
                  transaction: transaction,
                );
                if (mounted) await _load();
              },
              onTip: transaction.hasPlatformEarnings
                  ? () async {
                      await TipSheet.show(context, transaction: transaction);
                      if (mounted) await _load();
                    }
                  : null,
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.items});

  final List<BookingTransaction> items;

  @override
  Widget build(BuildContext context) {
    final completed = items.where((t) => t.hasPlatformEarnings);
    final earnings = completed.fold<int>(
      0,
      (sum, t) => sum + t.recordedEarningsCents,
    );
    final tips = completed.fold<int>(0, (sum, t) => sum + t.effectiveTipCents);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Earnings',
              value: Money.format(earnings),
              color: AppColors.textPrimary,
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: AppColors.border,
          ),
          Expanded(
            child: _MiniStat(
              label: 'Tips',
              value: Money.format(tips),
              color: AppColors.green,
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: AppColors.border,
          ),
          Expanded(
            child: _MiniStat(
              label: 'Bookings',
              value: '${completed.length}',
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
