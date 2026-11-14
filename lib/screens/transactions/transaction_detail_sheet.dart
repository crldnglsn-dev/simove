import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/booking_transaction.dart';
import '../../state/earnings_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import 'tip_sheet.dart';
import 'transaction_form_sheet.dart';

class TransactionDetailSheet extends StatefulWidget {
  const TransactionDetailSheet({super.key, required this.transaction});

  final BookingTransaction transaction;

  static Future<void> show(
    BuildContext context, {
    required BookingTransaction transaction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionDetailSheet(transaction: transaction),
    );
  }

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late BookingTransaction _transaction;

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
  }

  Future<void> _reload() async {
    final id = _transaction.id;
    if (id == null) return;
    final fresh = await context.read<EarningsProvider>().getById(id);
    if (fresh != null && mounted) {
      setState(() => _transaction = fresh);
    }
  }

  Future<void> _edit() async {
    final changed = await TransactionFormSheet.show(
      context,
      transaction: _transaction,
    );
    if (changed == true) await _reload();
  }

  Future<void> _tip() async {
    final changed = await TipSheet.show(context, transaction: _transaction);
    if (changed == true) await _reload();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete booking?'),
        content: Text(
          '${_transaction.bookingReference} and its earnings will be removed '
          'from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = _transaction.id;
    if (id == null) return;
    await context.read<EarningsProvider>().deleteTransaction(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = bookingStateColor(_transaction.bookingStatus);
    final pending = !_transaction.hasPlatformEarnings;

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _transaction.bookingReference,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                StatusPill(
                  label: _transaction.bookingStatus.label,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: _transaction.detectionSource.label,
                  color: AppColors.textSecondary,
                  icon: _transaction.detectionSource == DetectionSource.ocr
                      ? Icons.auto_awesome
                      : Icons.edit_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (pending ||
                _transaction.bookingStatus == BookingState.errorRequiresReview)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.gold),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This booking is not complete yet. The pending record is '
                        'saved safely; add the earnings manually if Angkas is no '
                        'longer showing them.',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            AppCard(
              gradient: const LinearGradient(
                colors: [AppColors.surfaceElevated, AppColors.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RECORDED EARNINGS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pending
                        ? '—'
                        : Money.format(_transaction.recordedEarningsCents),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: pending
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AmountRow(
                    label: 'Platform total earnings',
                    value: _transaction.platformEarningsCents,
                  ),
                  _AmountRow(
                    label:
                        'Tip${_transaction.tipIncludedInPlatformEarnings ? ' (already included)' : ''}',
                    value: _transaction.tipCents == 0
                        ? null
                        : (_transaction.tipIncludedInPlatformEarnings
                              ? 0
                              : _transaction.tipCents),
                    positive: true,
                  ),
                  const Divider(height: 22),
                  _AmountRow(
                    label: 'Fare to collect (not income)',
                    value: _transaction.fareToCollectCents,
                    muted: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  LabeledValue(
                    label: 'Booking time',
                    value: Dates.fullDate.format(_transaction.createdAt),
                  ),
                  LabeledValue(
                    label: 'Payment method',
                    value: _transaction.paymentMethod ?? '—',
                  ),
                  LabeledValue(
                    label: 'Tip type',
                    value: _transaction.tipCents > 0
                        ? _transaction.tipType.label
                        : '—',
                  ),
                  LabeledValue(
                    label: 'Detection confidence',
                    value: _transaction.detectionConfidence == null
                        ? '—'
                        : '${(_transaction.detectionConfidence! * 100).round()}%',
                  ),
                  if (_transaction.earningsDetectedAt != null)
                    LabeledValue(
                      label: 'Earnings read at',
                      value: Dates.time.format(
                        _transaction.earningsDetectedAt!,
                      ),
                    ),
                  if (_transaction.notes != null &&
                      _transaction.notes!.isNotEmpty) ...[
                    const Divider(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Notes',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _transaction.notes!,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _tip,
                    icon: const Icon(Icons.attach_money, size: 18),
                    label: const Text('Tip'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.positive = false,
  });

  final String label;
  final int? value;
  final bool muted;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted ? AppColors.textMuted : AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            value == null ? '—' : Money.format(value!),
            style: TextStyle(
              color: muted
                  ? AppColors.textMuted
                  : (positive ? AppColors.green : AppColors.textPrimary),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
