import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum PeriodCustomKind { day, month }

/// Opens the calendar used by Reports and Transactions.
Future<DateTime?> pickReportDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = initial ?? today;
  return showDatePicker(
    context: context,
    initialDate: start.isAfter(today) ? today : start,
    firstDate: DateTime(2024),
    lastDate: today,
    helpText: 'Select a date',
  );
}

/// Opens the month grid used by Reports and Transactions.
Future<DateTime?> pickReportMonth(BuildContext context, {DateTime? initial}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => MonthPickerDialog(initial: initial ?? DateTime.now()),
  );
}

class RangeIconButton extends StatelessWidget {
  const RangeIconButton({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        backgroundColor: active
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceElevated,
        foregroundColor: active ? AppColors.primary : AppColors.textSecondary,
        side: BorderSide(color: active ? AppColors.primary : AppColors.border),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class MonthPickerDialog extends StatefulWidget {
  const MonthPickerDialog({super.key, required this.initial});

  final DateTime initial;

  @override
  State<MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<MonthPickerDialog> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late int _year;
  final int _maxYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(2024, _maxYear);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            onPressed: _year > 2024 ? () => setState(() => _year--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '$_year',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: _year < _maxYear ? () => setState(() => _year++) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: [
            for (var i = 0; i < 12; i++)
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(DateTime(_year, i + 1)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Text(_months[i], style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
