import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../reports/expense_sheet.dart';
import 'transaction_form_sheet.dart';

enum _AddChoice { booking, expense }

/// One clear entry point for manual bookings and expenses.
/// Returns true when something was saved so callers can refresh.
Future<bool> showAddMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<_AddChoice>(
    context: context,
    useSafeArea: true,
    builder: (_) => const _AddMenuSheet(),
  );
  if (choice == null || !context.mounted) return false;

  switch (choice) {
    case _AddChoice.booking:
      final saved = await TransactionFormSheet.show(context);
      return saved == true;
    case _AddChoice.expense:
      final saved = await showAddExpense(context);
      return saved == true;
  }
}

class _AddMenuSheet extends StatelessWidget {
  const _AddMenuSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you want to add?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bookings add income. Expenses reduce what is left.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).pop(_AddChoice.booking),
            child: const _ChoiceTile(
              icon: Icons.two_wheeler_outlined,
              color: AppColors.primary,
              title: 'Add a booking',
              subtitle:
                  'Record a ride manually if automatic detection missed it.',
            ),
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).pop(_AddChoice.expense),
            child: const _ChoiceTile(
              icon: Icons.local_gas_station_outlined,
              color: AppColors.orange,
              title: 'Add an expense',
              subtitle: 'Gas, load, maintenance — subtracted from your net.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
