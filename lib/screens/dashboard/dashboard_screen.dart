import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../state/monitoring_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../help/income_help_sheet.dart';
import '../reports/expense_sheet.dart';
import '../setup/monitoring_setup_sheet.dart';
import '../transactions/tip_sheet.dart';
import '../transactions/transaction_detail_sheet.dart';
import '../transactions/transaction_form_sheet.dart';
import 'monitoring_health_sheet.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    this.onViewAllTransactions,
    this.onOpenSettings,
  });

  final VoidCallback? onViewAllTransactions;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final earnings = context.watch<EarningsProvider>();
    final monitoring = context.watch<MonitoringProvider>();
    final today = earnings.today;
    final recent = earnings.recent.take(6).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await earnings.refresh();
          await monitoring.refreshPermissions();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            _Header(onOpenSettings: onOpenSettings),
            const SizedBox(height: 18),
            _MonitoringCard(monitoring: monitoring),
            const SizedBox(height: 16),
            _HeroCard(earnings: earnings, monitoring: monitoring),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final saved = await TransactionFormSheet.show(context);
                      if (saved == true) await earnings.refresh();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add booking'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await showAddExpense(context);
                      if (saved == true) await earnings.refresh();
                    },
                    icon: const Icon(
                      Icons.local_gas_station_outlined,
                      size: 18,
                    ),
                    label: const Text('Add expense'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'This week',
                    value: Money.format(earnings.week.recordedEarningsCents),
                    icon: Icons.calendar_view_week_outlined,
                    accent: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(
                    label: 'This month',
                    value: Money.format(earnings.month.recordedEarningsCents),
                    icon: Icons.calendar_month_outlined,
                    accent: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Expenses today',
                    value: Money.format(today.expensesCents),
                    icon: Icons.local_gas_station_outlined,
                    accent: AppColors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(
                    label: 'Net today',
                    value: Money.format(today.netEarningsCents),
                    icon: Icons.savings_outlined,
                    accent: today.netEarningsCents >= 0
                        ? AppColors.green
                        : AppColors.red,
                    caption: 'after costs',
                  ),
                ),
              ],
            ),
            if (monitoring.activeTransaction != null) ...[
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Pending detection',
                subtitle: 'Saved locally while you switch apps',
              ),
              _PendingCard(
                transaction: monitoring.activeTransaction!,
                monitoring: monitoring,
              ),
            ],
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Recent bookings',
              subtitle: '${today.bookingCount} recorded today',
              actionLabel: 'View all',
              onAction: onViewAllTransactions,
            ),
            if (recent.isEmpty)
              AppCard(
                padding: EdgeInsets.zero,
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No bookings yet',
                  message: 'Start monitoring or add a ride manually to see your earnings here.',
                  actionLabel: 'Add booking',
                  onAction: () => TransactionFormSheet.show(context),
                ),
              )
            else
              for (final transaction in recent) ...[
                TransactionTile(
                  transaction: transaction,
                  onTap: () async {
                    await TransactionDetailSheet.show(
                      context,
                      transaction: transaction,
                    );
                    if (context.mounted) await earnings.refresh();
                  },
                  onTip: transaction.hasPlatformEarnings
                      ? () async {
                          await TipSheet.show(
                            context,
                            transaction: transaction,
                          );
                          if (context.mounted) await earnings.refresh();
                        }
                      : null,
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Image.asset(
            'assets/logo/simove_icon_512.png',
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            errorBuilder: (context, child, error) => const Icon(
              Icons.two_wheeler_rounded,
              color: Color(0xFF04121F),
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SIMOVE',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Rider earnings, tracked automatically',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenSettings,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
          ),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.monitoring});

  final MonitoringProvider monitoring;

  Color get _color => switch (monitoring.status) {
    MonitoringStatus.monitoring => AppColors.green,
    MonitoringStatus.starting => AppColors.primary,
    MonitoringStatus.needsPermission => AppColors.gold,
    MonitoringStatus.error => AppColors.red,
    MonitoringStatus.off => AppColors.textMuted,
  };

  String get _title => switch (monitoring.status) {
    MonitoringStatus.monitoring => 'Automatic detection is on',
    MonitoringStatus.starting => 'Starting automatic detection…',
    MonitoringStatus.needsPermission => 'One permission is needed',
    MonitoringStatus.error => 'Automatic detection stopped',
    MonitoringStatus.off => 'Automatic detection is off',
  };

  String get _detail => switch (monitoring.status) {
    MonitoringStatus.monitoring => monitoring.statusDetail,
    MonitoringStatus.needsPermission =>
      'Allow usage access so SIMOVE knows when Angkas is open.',
    MonitoringStatus.error => monitoring.lastError ?? monitoring.lastReason,
    MonitoringStatus.off =>
      'Turn it on so completed rides are recorded automatically.',
    MonitoringStatus.starting => 'Waiting for Android screen capture…',
  };

  String get _buttonLabel => switch (monitoring.status) {
    MonitoringStatus.monitoring => 'Health',
    MonitoringStatus.starting => 'Wait…',
    MonitoringStatus.needsPermission => 'Fix',
    MonitoringStatus.error => 'Retry',
    MonitoringStatus.off => 'Start',
  };

  IconData get _buttonIcon => switch (monitoring.status) {
    MonitoringStatus.monitoring => Icons.monitor_heart_outlined,
    MonitoringStatus.starting => Icons.hourglass_top_rounded,
    MonitoringStatus.needsPermission => Icons.build_outlined,
    MonitoringStatus.error => Icons.refresh_rounded,
    MonitoringStatus.off => Icons.play_arrow_rounded,
  };

  Future<void> _primaryAction(BuildContext context) async {
    if (!monitoring.permissions.usageAccess) {
      await showMonitoringSetup(context);
      return;
    }
    if (!monitoring.isMonitoring) {
      await monitoring.startMonitoring();
      if (context.mounted && !monitoring.isMonitoring) {
        await showMonitoringHealth(context);
      }
      return;
    }
    await showMonitoringHealth(context);
  }

  @override
  Widget build(BuildContext context) {
    final healthy = monitoring.isMonitoring;
    final needsAttention =
        monitoring.status == MonitoringStatus.off ||
        monitoring.status == MonitoringStatus.error ||
        monitoring.status == MonitoringStatus.needsPermission;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => showMonitoringHealth(context),
      gradient: LinearGradient(
        colors: [
          AppColors.surfaceElevated,
          _color.withValues(alpha: healthy ? 0.06 : 0.11),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderColor: _color.withValues(alpha: healthy ? 0.25 : 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _color.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (monitoring.isBusy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (healthy)
                OutlinedButton.icon(
                  onPressed: () => _primaryAction(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                  ),
                  icon: Icon(_buttonIcon, size: 16),
                  label: Text(
                    _buttonLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => _primaryAction(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                  ),
                  icon: Icon(_buttonIcon, size: 17),
                  label: Text(
                    _buttonLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (needsAttention) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Rides completed while this is off are not recorded.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.gold.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.earnings, required this.monitoring});

  final EarningsProvider earnings;
  final MonitoringProvider monitoring;

  @override
  Widget build(BuildContext context) {
    final today = earnings.today;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0C2745), Color(0xFF0A1A2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "TODAY'S INCOME",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => showIncomeHelp(context),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              StatusPill(
                label: monitoring.isMonitoring ? 'AUTO' : 'MANUAL',
                color: monitoring.isMonitoring
                    ? AppColors.primary
                    : AppColors.textMuted,
                icon: monitoring.isMonitoring
                    ? Icons.auto_awesome
                    : Icons.edit_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(today.recordedEarningsCents),
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.8,
                color: AppColors.textPrimary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            today.bookingCount == 0
                ? 'No completed bookings yet today'
                : '${today.bookingCount} booking${today.bookingCount == 1 ? '' : 's'} completed today',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                _HeroStat(
                  label: 'App earnings',
                  value: Money.format(today.platformEarningsCents),
                  color: AppColors.gold,
                ),
                const _VerticalDivider(),
                _HeroStat(
                  label: 'Tips',
                  value: Money.format(today.tipsCents),
                  color: AppColors.green,
                ),
                const _VerticalDivider(),
                _HeroStat(
                  label: 'Passenger paid',
                  value: Money.format(today.fareCollectedCents),
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => showIncomeHelp(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text(
                      'Passenger payment is cash you collect — not income.',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (today.pendingCount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 13,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${today.pendingCount} booking${today.pendingCount == 1 ? '' : 's'} still waiting for earnings',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
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

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.transaction, required this.monitoring});

  final BookingTransaction transaction;
  final MonitoringProvider monitoring;

  @override
  Widget build(BuildContext context) {
    final statusColor = bookingStateColor(transaction.bookingStatus);
    return AppCard(
      borderColor: statusColor.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors_rounded, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  transaction.bookingReference,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              StatusPill(
                label: transaction.bookingStatus.label,
                color: statusColor,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            monitoring.lastReason,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => TransactionDetailSheet.show(
                    context,
                    transaction: transaction,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Details', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => TransactionFormSheet.show(
                    context,
                    transaction: transaction,
                  ),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  child: const Text(
                    'Add earnings',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
