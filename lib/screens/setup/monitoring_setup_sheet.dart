import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../state/monitoring_provider.dart';
import '../../state/settings_provider.dart';

Future<void> showMonitoringSetup(
  BuildContext context, {
  bool firstRun = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MonitoringSetupSheet(firstRun: firstRun),
  );
  if (context.mounted) {
    await context.read<SettingsProvider>().setOnboardingCompleted(true);
  }
}

class MonitoringSetupSheet extends StatefulWidget {
  const MonitoringSetupSheet({super.key, this.firstRun = false});

  final bool firstRun;

  @override
  State<MonitoringSetupSheet> createState() => _MonitoringSetupSheetState();
}

class _MonitoringSetupSheetState extends State<MonitoringSetupSheet>
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

  Future<void> _start(MonitoringProvider monitoring) async {
    if (!monitoring.permissions.usageAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow usage access first so SIMOVE can tell when Angkas is open.',
          ),
        ),
      );
      await monitoring.openSettings('usage');
      return;
    }
    await monitoring.startMonitoring();
    if (!mounted) return;
    if (monitoring.isMonitoring) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monitoring started. Open Angkas when you go online.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final monitoring = context.watch<MonitoringProvider>();
    final permissions = monitoring.permissions;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF04121F),
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.firstRun
                  ? 'Set up automatic detection'
                  : 'Monitoring permissions',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SIMOVE reads only the Angkas booking panel that is visible on '
              'screen. Screenshots never leave your phone and passenger details '
              'are never stored.',
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            _PermissionTile(
              icon: Icons.query_stats,
              title: 'Usage access',
              description:
                  'Tells SIMOVE when Angkas is in the foreground so OCR only runs on the right screen.',
              granted: permissions.usageAccess,
              required: true,
              buttonLabel: 'Open',
              onPressed: () => monitoring.openSettings('usage'),
            ),
            const SizedBox(height: 10),
            _PermissionTile(
              icon: Icons.notifications_active_outlined,
              title: 'Notifications',
              description:
                  'Shows the required monitoring notification and keeps Android from hiding the service.',
              granted: permissions.notifications,
              buttonLabel: 'Allow',
              onPressed: () => monitoring.openSettings('notifications'),
            ),
            const SizedBox(height: 10),
            _PermissionTile(
              icon: Icons.screen_share_outlined,
              title: 'Screen capture',
              description:
                  'Android asks for permission each time monitoring starts. Choose “Share entire screen” so Angkas stays visible while you switch apps.',
              granted: permissions.captureRunning,
              required: true,
              buttonLabel: permissions.captureRunning ? 'Active' : 'Start',
              onPressed: () => _start(monitoring),
            ),
            const SizedBox(height: 10),
            _PermissionTile(
              icon: Icons.battery_saver_outlined,
              title: 'Battery optimisation',
              description:
                  'Optional. Exempting SIMOVE helps Android keep monitoring alive during long shifts.',
              granted: permissions.batteryOptimizationIgnored,
              buttonLabel: 'Settings',
              onPressed: () => monitoring.openSettings('battery'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SIMOVE never taps Angkas buttons, accepts rides, or stores '
                      'passenger names, numbers, or addresses. Automatic detection '
                      'works while Angkas is visible; a pending booking is kept '
                      'safely while you use Maps or Waze.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    monitoring.isBusy ? null : () => _start(monitoring),
                icon: monitoring.isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  monitoring.isMonitoring
                      ? 'Monitoring is active'
                      : 'Start monitoring',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.firstRun ? 'Not now' : 'Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onPressed,
    required this.buttonLabel,
    this.required = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool required;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: granted
                  ? AppColors.green.withValues(alpha: 0.12)
                  : AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: granted ? AppColors.green : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    if (required) ...[
                      const SizedBox(width: 6),
                      const Text(
                        'REQUIRED',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          granted
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: StatusPill(
                    label: 'Granted',
                    color: AppColors.green,
                    compact: true,
                  ),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
        ],
      ),
    );
  }
}
