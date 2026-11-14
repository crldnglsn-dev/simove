import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../state/monitoring_provider.dart';
import '../../state/settings_provider.dart';
import '../../widgets/common.dart';
import '../setup/monitoring_setup_sheet.dart';

/// Plain-language health check for automatic booking detection.
Future<void> showMonitoringHealth(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const MonitoringHealthSheet(),
  );
}

class MonitoringHealthSheet extends StatefulWidget {
  const MonitoringHealthSheet({super.key});

  @override
  State<MonitoringHealthSheet> createState() => _MonitoringHealthSheetState();
}

class _MonitoringHealthSheetState extends State<MonitoringHealthSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<MonitoringProvider>().refreshPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final monitoring = context.watch<MonitoringProvider>();
    final settings = context.watch<SettingsProvider>();
    final permissions = monitoring.permissions;
    final healthy = monitoring.isMonitoring && permissions.captureRunning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (healthy ? AppColors.green : AppColors.gold)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    healthy
                        ? Icons.verified_outlined
                        : Icons.health_and_safety_outlined,
                    color: healthy ? AppColors.green : AppColors.gold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy ? 'Monitoring is healthy' : 'Fix monitoring',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        settings.targetPackage,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!healthy)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 17, color: AppColors.gold),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Automatic detection only works while SIMOVE is allowed to '
                        'run and screen capture is on. Rides you complete while it '
                        'is off are not recorded automatically.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _HealthRow(
              title: 'Usage access',
              detail: permissions.usageAccess
                  ? 'Allowed — SIMOVE can see when Angkas is open'
                  : 'Needed so SIMOVE knows when to read Angkas',
              ok: permissions.usageAccess,
              actionLabel: permissions.usageAccess ? null : 'Allow',
              onAction: () => monitoring.openSettings('usage'),
            ),
            _HealthRow(
              title: 'Screen capture',
              detail: permissions.captureRunning
                  ? 'On — reading the visible screen'
                  : 'Off — start it to record rides automatically',
              ok: permissions.captureRunning,
              actionLabel: permissions.captureRunning ? null : 'Start',
              onAction: () => showMonitoringSetup(context),
            ),
            _HealthRow(
              title: 'Battery unrestricted',
              detail: permissions.batteryOptimizationIgnored
                  ? 'Allowed to run in the background'
                  : 'Recommended on TECNO so monitoring is not frozen',
              ok: permissions.batteryOptimizationIgnored,
              actionLabel: permissions.batteryOptimizationIgnored
                  ? null
                  : 'Settings',
              onAction: () => monitoring.openSettings('battery'),
            ),
            _HealthRow(
              title: 'Auto-start allowed',
              detail:
                  'On TECNO / Infinix / itel, enable Auto-start in App info',
              ok: false,
              actionLabel: 'App info',
              onAction: () => monitoring.openSettings('app'),
              neutral: true,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TECNO phone checklist',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. App info → Battery → choose Unrestricted.\n'
                    '2. Phone Manager / Auto-start → allow SIMOVE.\n'
                    '3. Recents screen → lock SIMOVE so it is not cleared.\n'
                    '4. Keep the red screen-capture icon visible while riding.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.55,
                    ),
                  ),
                  if (monitoring.lastOcrAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last Angkas screen read '
                      '${Dates.time.format(monitoring.lastOcrAt!)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    monitoring.lastReason,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: monitoring.isBusy
                    ? null
                    : () async {
                        if (!permissions.usageAccess) {
                          await monitoring.openSettings('usage');
                        } else if (!monitoring.isMonitoring) {
                          await monitoring.startMonitoring();
                        } else {
                          await monitoring.refreshPermissions();
                        }
                      },
                icon: monitoring.isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  monitoring.isBusy
                      ? 'Please wait…'
                      : !permissions.usageAccess
                      ? 'Allow usage access'
                      : monitoring.isMonitoring
                      ? 'Re-check health'
                      : 'Start monitoring',
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.title,
    required this.detail,
    required this.ok,
    this.actionLabel,
    this.onAction,
    this.neutral = false,
  });

  final String title;
  final String detail;
  final bool ok;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral
        ? AppColors.textSecondary
        : ok
        ? AppColors.green
        : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        borderColor: color.withValues(alpha: 0.22),
        child: Row(
          children: [
            Icon(
              neutral
                  ? Icons.tune
                  : ok
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
