import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../services/earnings_exporter.dart';
import '../../state/earnings_provider.dart';
import '../../state/monitoring_provider.dart';
import '../../state/settings_provider.dart';
import '../../widgets/common.dart';
import '../dashboard/monitoring_health_sheet.dart';
import '../help/income_help_sheet.dart';
import '../setup/monitoring_setup_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;

  Future<void> _onAutoMonitoringChanged(
    bool value,
    SettingsProvider settings,
    MonitoringProvider monitoring,
  ) async {
    await settings.setAutoMonitoring(value);
    if (!mounted) return;
    if (value && !monitoring.isMonitoring) {
      if (!monitoring.permissions.usageAccess) {
        await showMonitoringSetup(context);
      } else {
        await monitoring.startMonitoring();
      }
    } else if (!value && monitoring.isMonitoring) {
      await monitoring.stopMonitoring();
    }
  }

  Future<void> _export({required bool csv}) async {
    setState(() => _exporting = true);
    final earnings = context.read<EarningsProvider>();
    try {
      final transactions = await earnings.history(limit: 100000);
      final expenses = await earnings.expensesBetween(
        DateTime(2000),
        DateTime(2100),
      );
      if (!mounted) return;
      if (csv) {
        await EarningsExporter.shareCsv(
          transactions: transactions,
          expenses: expenses,
        );
      } else {
        await EarningsExporter.shareJson(
          transactions: transactions,
          expenses: expenses,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editTargetPackage(
    SettingsProvider settings,
    MonitoringProvider monitoring,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PackageDialog(initialValue: settings.targetPackage),
    );
    if (result == null || result.isEmpty) return;
    await monitoring.applyTargetPackage(result);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Monitoring target set to $result')));
  }

  Future<void> _clearData(EarningsProvider earnings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all local data?'),
        content: const Text(
          'All bookings, tips and expenses on this device will be permanently '
          'deleted. Export a backup first if you need a copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await earnings.clearAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local earnings data cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final monitoring = context.watch<MonitoringProvider>();
    final permissions = monitoring.permissions;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Control monitoring, privacy and local data',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          _MonitoringStatusCard(monitoring: monitoring),
          const SizedBox(height: 14),
          _Section(
            title: 'Monitoring',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.autoMonitoring,
                onChanged: monitoring.isBusy
                    ? null
                    : (value) =>
                          _onAutoMonitoringChanged(value, settings, monitoring),
                title: const Text('Automatic detection'),
                subtitle: const Text(
                  'Remembers to resume monitoring when you open SIMOVE.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              const Divider(height: 20),
              _SettingsTile(
                icon: Icons.query_stats,
                title: 'Usage access',
                subtitle: permissions.usageAccess
                    ? 'Granted — SIMOVE can tell when Angkas is open'
                    : 'Required to detect when Angkas is open',
                trailing: permissions.usageAccess
                    ? const StatusPill(
                        label: 'Granted',
                        color: AppColors.green,
                        compact: true,
                      )
                    : TextButton(
                        onPressed: () => monitoring.openSettings('usage'),
                        child: const Text('Allow'),
                      ),
              ),
              _SettingsTile(
                icon: Icons.screen_share_outlined,
                title: 'Screen capture',
                subtitle: permissions.captureRunning
                    ? 'Active — reading the visible screen only'
                    : 'Required — starts through Android’s consent dialog',
                trailing: permissions.captureRunning
                    ? const StatusPill(
                        label: 'Active',
                        color: AppColors.green,
                        compact: true,
                      )
                    : TextButton(
                        onPressed: () => showMonitoringSetup(context),
                        child: const Text('Start'),
                      ),
              ),
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Notifications',
                subtitle: 'Shows the required monitoring notice',
                trailing: permissions.notifications
                    ? const StatusPill(
                        label: 'Granted',
                        color: AppColors.green,
                        compact: true,
                      )
                    : TextButton(
                        onPressed: () =>
                            monitoring.openSettings('notifications'),
                        child: const Text('Allow'),
                      ),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notification hints (optional)',
                subtitle: 'Reads Angkas notification titles as a hint only. Never used alone.',
                trailing: permissions.notificationListener
                    ? const StatusPill(
                        label: 'On',
                        color: AppColors.primary,
                        compact: true,
                      )
                    : TextButton(
                        onPressed: () =>
                            monitoring.openSettings('notificationListener'),
                        child: const Text('Enable'),
                      ),
              ),
              _SettingsTile(
                icon: Icons.battery_saver_outlined,
                title: 'Battery: Unrestricted',
                subtitle: permissions.batteryOptimizationIgnored
                    ? 'SIMOVE is exempt from battery restrictions'
                    : 'On TECNO, choose Unrestricted in App info → Battery',
                trailing: TextButton(
                  onPressed: () => monitoring.openSettings('battery'),
                  child: const Text('Settings'),
                ),
              ),
              _SettingsTile(
                icon: Icons.restart_alt,
                title: 'Auto-start (TECNO / Infinix / itel)',
                subtitle:
                    'Allow SIMOVE to keep running after the phone restarts.',
                trailing: TextButton(
                  onPressed: () => monitoring.openSettings('app'),
                  child: const Text('App info'),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.22),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.phone_android_outlined,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'TECNO phones can freeze background apps. In App info → '
                        'Battery choose Unrestricted, allow Auto-start, and lock '
                        'SIMOVE in the recent-apps screen.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Floating tracker',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.overlayEnabled,
                onChanged: (value) async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (value && !permissions.overlay) {
                    await monitoring.openSettings('overlay');
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Allow display over other apps, then enable the tracker again.',
                        ),
                      ),
                    );
                    return;
                  }
                  await monitoring.setOverlayEnabled(value);
                },
                title: const Text('Show income over other apps'),
                subtitle: const Text(
                  'Movable mini tracker with today’s income and monitoring status.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              if (!permissions.overlay)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => monitoring.openSettings('overlay'),
                    child: const Text('Grant overlay permission'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Data',
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : () => _export(csv: true),
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('Export CSV'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : () => _export(csv: false),
                      icon: const Icon(Icons.data_object_outlined, size: 18),
                      label: const Text('Backup JSON'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.delete_outline,
                title: 'Clear local data',
                subtitle:
                    'Deletes every booking, tip and expense on this phone',
                trailing: TextButton(
                  onPressed: () => _clearData(context.read<EarningsProvider>()),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Display',
            children: [
              DropdownButtonFormField<String>(
                initialValue: settings.currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: [
                  for (final entry in Money.supportedCurrencies.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text('${entry.key}  (${entry.value})'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) settings.setCurrency(value);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'SIMOVE reads Philippine peso amounts from Angkas. Other '
                'currencies only change formatting for manual entries.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Help',
            children: [
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'How income is computed',
                subtitle:
                    'App earnings + tips. Passenger payment is not income.',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showIncomeHelp(context),
              ),
              _SettingsTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Monitoring health check',
                subtitle: 'See what is working and fix anything that is not.',
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showMonitoringHealth(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AdvancedSection(
            settings: settings,
            monitoring: monitoring,
            onEditTarget: () => _editTargetPackage(settings, monitoring),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Privacy & limits',
            children: const [
              _PrivacyPoint(
                icon: Icons.lock_outline,
                text: 'OCR runs on-device. Screenshots are never uploaded or saved.',
              ),
              _PrivacyPoint(
                icon: Icons.person_off_outlined,
                text:
                    'Passenger names, phone numbers and addresses are never stored. '
                    'Deduplication uses a salted one-way hash.',
              ),
              _PrivacyPoint(
                icon: Icons.screen_share_outlined,
                text:
                    'Only the visible screen can be read. When Angkas is behind '
                    'Maps or Waze, the last pending booking is preserved.',
              ),
              _PrivacyPoint(
                icon: Icons.block_outlined,
                text:
                    'SIMOVE never accepts or rejects rides and never taps Angkas '
                    'controls. It is a read-only earnings tracker.',
              ),
              _PrivacyPoint(
                icon: Icons.warning_amber_rounded,
                text:
                    'OCR can misread a value. Review flagged bookings and correct '
                    'them only while safely stopped.',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'About',
            children: [
              const _SettingsTile(
                icon: Icons.info_outline,
                title: 'SIMOVE',
                subtitle: 'Carl John Dinglasan • Version 1.0.0 • Offline-first earnings tracker',
              ),
              const _SettingsTile(
                icon: Icons.two_wheeler_outlined,
                title: 'Built for Angkas riders',
                subtitle: 'Automatic booking detection with manual control when OCR cannot read the screen.',
              ),
              if (monitoring.notificationHint != null)
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Last notification hint',
                  subtitle: monitoring.notificationHint!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonitoringStatusCard extends StatelessWidget {
  const _MonitoringStatusCard({required this.monitoring});

  final MonitoringProvider monitoring;

  @override
  Widget build(BuildContext context) {
    final healthy = monitoring.isMonitoring;
    final color = healthy ? AppColors.green : AppColors.gold;
    return AppCard(
      onTap: () => showMonitoringHealth(context),
      borderColor: color.withValues(alpha: 0.3),
      gradient: LinearGradient(
        colors: [AppColors.surfaceElevated, color.withValues(alpha: 0.07)],
      ),
      child: Row(
        children: [
          Icon(
            healthy
                ? Icons.verified_outlined
                : Icons.health_and_safety_outlined,
            size: 22,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  healthy ? 'Monitoring is healthy' : monitoring.statusLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  monitoring.statusDetail,
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
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => showMonitoringHealth(context),
            child: Text(healthy ? 'Check' : 'Fix'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.settings,
    required this.monitoring,
    required this.onEditTarget,
  });

  final SettingsProvider settings;
  final MonitoringProvider monitoring;
  final VoidCallback onEditTarget;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: const Text(
            'ADVANCED',
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          subtitle: const Text(
            'Detection threshold, diagnostics and Angkas package',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textMuted,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'OCR confidence threshold',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                Text(
                  '${(settings.minConfidence * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Slider(
              value: settings.minConfidence.clamp(0.35, 0.95),
              min: 0.35,
              max: 0.95,
              divisions: 12,
              label: '${(settings.minConfidence * 100).round()}%',
              onChanged: (value) => monitoring.applyConfidence(value),
            ),
            const Text(
              'Higher values need a clearer screen before a ride is saved as '
              'verified. Lower-confidence reads stay flagged for review.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detection diagnostics',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    monitoring.lastReason,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  if (monitoring.lastOcrAt != null)
                    Text(
                      'Last frame: ${Dates.fullDate.format(monitoring.lastOcrAt!)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (monitoring.lastScreen?.signals.isNotEmpty == true)
                    Text(
                      'Signals: ${monitoring.lastScreen!.signals.take(6).join(', ')}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (monitoring.activeTransaction != null)
                    Text(
                      'Open booking: ${monitoring.activeTransaction!.bookingReference}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps, size: 20),
              title: const Text(
                'Angkas app package',
                style: TextStyle(fontSize: 13.5),
              ),
              subtitle: Text(
                settings.targetPackage,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: onEditTarget,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns its own text controller so the field stays valid for the whole route
/// lifetime. Disposing the controller right after `showDialog` returns can
/// trip a framework assertion while the dialog is still animating out.
class _PackageDialog extends StatefulWidget {
  const _PackageDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<_PackageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Angkas app package'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autocorrect: false,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Android package name',
              hintText: 'com.angkas.rider',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'SIMOVE only scans frames while this package is in the '
            'foreground. Change it only if you know the rider app package.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
