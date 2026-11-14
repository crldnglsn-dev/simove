import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Explains, in plain words, which numbers count as income.
Future<void> showIncomeHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _IncomeHelpSheet(),
  );
}

class _IncomeHelpSheet extends StatelessWidget {
  const _IncomeHelpSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How your income is counted',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'SIMOVE keeps three numbers apart so your daily total is honest.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            const _HelpRow(
              icon: Icons.auto_awesome,
              color: AppColors.primary,
              title: 'App earnings = income',
              body: 'This is the “Total Earnings” amount Angkas shows for the ride. It is what you actually earn.',
            ),
            const _HelpRow(
              icon: Icons.volunteer_activism_outlined,
              color: AppColors.green,
              title: 'Tips = income',
              body: 'A tip you add is counted only if it is not already inside the app amount. Tick “Already included” when Angkas shows it in Total Earnings.',
            ),
            const _HelpRow(
              icon: Icons.payments_outlined,
              color: AppColors.gold,
              title: 'Passenger payment = not income',
              body: '“Fare To Collect” or “Total Payment” is the money the passenger hands you. It is shown for reference only and is never added to income.',
            ),
            const _HelpRow(
              icon: Icons.local_gas_station_outlined,
              color: AppColors.orange,
              title: 'Expenses reduce what is left',
              body: 'Gas, load and other costs are deducted only in “Net today”. Your income total stays the same.',
            ),
            const SizedBox(height: 8),
            const AppCard(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: AppColors.gold,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Example: App earnings ₱75.00 + tip ₱20.00 = ₱95.00 income. '
                      'If the passenger pays ₱95.00 cash, that ₱95.00 is not added again.',
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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
