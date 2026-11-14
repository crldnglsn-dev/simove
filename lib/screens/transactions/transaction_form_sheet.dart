import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/utils/payment_methods.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../state/monitoring_provider.dart';

class TransactionFormSheet extends StatefulWidget {
  const TransactionFormSheet({super.key, this.transaction});

  final BookingTransaction? transaction;

  static Future<bool?> show(
    BuildContext context, {
    BookingTransaction? transaction,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionFormSheet(transaction: transaction),
    );
  }

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _earnings;
  late final TextEditingController _fare;
  late final TextEditingController _tip;
  late final TextEditingController _notes;
  late String _paymentMethod;
  late TipType _tipType;
  late bool _tipIncluded;
  late DateTime _createdAt;
  bool _saving = false;

  static const _paymentMethods = PaymentMethods.all;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _earnings = TextEditingController(
      text: t?.platformEarningsCents == null
          ? ''
          : Money.format(t!.platformEarningsCents!, withSymbol: false),
    );
    _fare = TextEditingController(
      text: t?.fareToCollectCents == null
          ? ''
          : Money.format(t!.fareToCollectCents!, withSymbol: false),
    );
    _tip = TextEditingController(
      text: (t?.tipCents ?? 0) == 0
          ? ''
          : Money.format(t!.tipCents, withSymbol: false),
    );
    _notes = TextEditingController(text: t?.notes ?? '');
    _paymentMethod = PaymentMethods.normalize(t?.paymentMethod);
    _tipType = t?.tipType ?? TipType.cash;
    _tipIncluded = t?.tipIncludedInPlatformEarnings ?? false;
    _createdAt = t?.createdAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _earnings.dispose();
    _fare.dispose();
    _tip.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _createdAt = DateTime(
        date.year,
        date.month,
        date.day,
        _createdAt.hour,
        _createdAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _createdAt = DateTime(
        _createdAt.year,
        _createdAt.month,
        _createdAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final earnings = Money.parseToCents(_earnings.text);
    final fare = Money.parseToCents(_fare.text);
    final tip = Money.parseToCents(_tip.text) ?? 0;
    if (earnings == null || fare == null) return;

    setState(() => _saving = true);
    final earningsProvider = context.read<EarningsProvider>();
    final monitoring = context.read<MonitoringProvider>();
    try {
      if (!_isEditing) {
        await earningsProvider.addManual(
          platformEarningsCents: earnings,
          fareToCollectCents: fare,
          paymentMethod: _paymentMethod,
          tipCents: tip,
          tipType: _tipType,
          tipIncluded: _tipIncluded,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          createdAt: _createdAt,
        );
      } else {
        final original = widget.transaction!;
        final notes = _notes.text.trim();
        await earningsProvider.updateTransaction(
          original.copyWith(
            platformEarningsCents: earnings,
            fareToCollectCents: fare,
            paymentMethod: _paymentMethod,
            tipCents: tip,
            tipType: _tipType,
            tipIncludedInPlatformEarnings: _tipIncluded,
            notes: notes.isEmpty ? null : notes,
            clearNotes: notes.isEmpty,
            bookingStatus: BookingState.recorded,
            createdAt: _createdAt,
            earningsDetectedAt: original.earningsDetectedAt ?? _createdAt,
            endedAt: original.endedAt,
            isManuallyEdited: true,
          ),
        );
      }
      await monitoring.syncOverlay(force: true);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save booking: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _isEditing;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                editing ? 'Edit booking' : 'Add booking manually',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                editing
                    ? 'Manual corrections are preserved and will not be overwritten by OCR.'
                    : 'Use this when automatic detection missed a ride.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _AmountField(
                      controller: _earnings,
                      label: 'Total earnings',
                      hint: '75.00',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AmountField(
                      controller: _fare,
                      label: 'Fare to collect',
                      hint: '95.00',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  for (final method in _paymentMethods)
                    DropdownMenuItem(value: method, child: Text(method)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(Dates.dateOnly.format(_createdAt)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Time',
                          prefixIcon: Icon(Icons.schedule),
                        ),
                        child: Text(Dates.time.format(_createdAt)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Tip',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<TipType>(
                    value: _tipType,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                    items: [
                      for (final type in TipType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text('${type.label} tip'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _tipType = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _AmountField(
                controller: _tip,
                label: 'Tip amount',
                hint: '0.00',
                required: false,
                helper: 'Added on top of platform earnings.',
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _tipIncluded,
                onChanged: (value) => setState(() => _tipIncluded = value),
                title: const Text(
                  'Tip already included in Total Earnings',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Turn this on to avoid counting the same tip twice.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 52),
                    child: Icon(Icons.notes),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(editing ? 'Save changes' : 'Save booking'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.hint,
    this.required = true,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '${Money.symbol} ',
        helperText: helper,
        helperMaxLines: 2,
      ),
      validator: (value) {
        if (!required && (value == null || value.trim().isEmpty)) return null;
        final cents = Money.parseToCents(value ?? '');
        if (cents == null) return 'Enter a valid amount';
        if (required && cents <= 0) return 'Must be above zero';
        return null;
      },
    );
  }
}
