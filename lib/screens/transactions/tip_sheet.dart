import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../state/monitoring_provider.dart';

class TipSheet extends StatefulWidget {
  const TipSheet({super.key, required this.transaction});

  final BookingTransaction transaction;

  static Future<bool?> show(
    BuildContext context, {
    required BookingTransaction transaction,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TipSheet(transaction: transaction),
    );
  }

  @override
  State<TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<TipSheet> {
  late final TextEditingController _amount;
  late TipType _tipType;
  late bool _included;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.transaction.tipCents == 0
          ? ''
          : Money.format(widget.transaction.tipCents, withSymbol: false),
    );
    _tipType = widget.transaction.tipType;
    _included = widget.transaction.tipIncludedInPlatformEarnings;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final cents = remove ? 0 : Money.parseToCents(_amount.text);
    if (cents == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid tip amount.')),
      );
      return;
    }
    setState(() => _saving = true);
    final earnings = context.read<EarningsProvider>();
    final monitoring = context.read<MonitoringProvider>();
    try {
      await earnings.setTip(
        widget.transaction,
        tipCents: cents,
        tipType: _tipType,
        included: cents == 0 ? false : _included,
      );
      await monitoring.syncOverlay(force: true);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save tip: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tip for ${transaction.bookingReference}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tips are stored separately from the displayed Angkas earnings. '
            'If the tip is already part of Total Earnings, mark it below to avoid double counting.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tip amount',
              prefixText: '${Money.symbol} ',
              hintText: '20.00',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TipType>(
                  initialValue: _tipType,
                  decoration: const InputDecoration(labelText: 'Tip type'),
                  items: [
                    for (final type in TipType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _tipType = value);
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _included,
            onChanged: (value) => setState(() => _included = value),
            title: const Text(
              'Already included in Total Earnings',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Recorded earnings will not add this tip again.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save tip'),
            ),
          ),
          if (transaction.tipCents > 0) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _saving ? null : () => _save(remove: true),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('Remove tip'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
