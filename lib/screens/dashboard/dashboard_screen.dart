import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../state/monitoring_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import '../setup/monitoring_setup_sheet.dart';
import '../transactions/tip_sheet.dart';
import '../transactions/transaction_detail_sheet.dart';
import '../transactions/transaction_form_sheet.dart';

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
                  message:
                      'Start monitoring or add a ride manually to see your earnings here.',
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
          child: const Icon(
            Icons.two_wheeler_rounded,
            color: Color(0xFF04121F),
            size: 24,
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

  Future<void> _toggle(BuildContext context) async {
    if (!monitoring.isMonitoring &&
        !monitoring.permissions.usageAccess) {
      await showMonitoringSetup(context);
      return;
    }
    await monitoring.toggleMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    final lastRead = monitoring.lastOcrAt;
    final subtitle = monitoring.isMonitoring && lastRead != null
        ? 'Last Angkas screen read ${Dates.time.format(lastRead)}'
        : monitoring.lastReason;

    return AppCard(
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(
        colors: [
          AppColors.surfaceElevated,
          _color.withValues(alpha: 0.06),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderColor: _color.withValues(alpha: 0.25),
      child: Row(
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
                  monitoring.statusLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
                if (monitoring.status == MonitoringStatus.error &&
                    monitoring.lastError != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    monitoring.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.red,
                    ),
                  ),
                ],
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
          else
            monitoring.isMonitoring
                ? OutlinedButton.icon(
                    onPressed: () => _toggle(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 17),
                    label: const Text(
                      'Stop',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => _toggle(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text(
                      'Start',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
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
                "TODAY'S EARNINGS",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textMuted,
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
            '${today.bookingCount} booking${today.bookingCount == 1 ? '' : 's'} recorded today',
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
                  label: 'Tips',
                  value: Money.format(today.tipsCents),
                  color: AppColors.green,
                ),
                const _VerticalDivider(),
                _HeroStat(
                  label: 'Fare collected',
                  value: Money.format(today.fareCollectedCents),
                  color: AppColors.textPrimary,
                ),
                const _VerticalDivider(),
                _HeroStat(
                  label: 'Platform',
                  value: Money.format(today.platformEarningsCents),
                  color: AppColors.gold,
                ),
              ],
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
                Text(
                  '${today.pendingCount} booking${today.pendingCount == 1 ? '' : 's'} waiting for earnings',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.gold,
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
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.textMuted,
            ),
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
                  child: const Text(
                    'Details',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => TransactionFormSheet.show(
                    context,
                    transaction: transaction,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
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
