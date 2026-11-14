import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../data/models/booking_transaction.dart';
import 'common.dart';

Color bookingStateColor(BookingState state) => switch (state) {
  BookingState.idle => AppColors.textMuted,
  BookingState.bookingDetected => AppColors.gold,
  BookingState.waitingForEarnings => AppColors.gold,
  BookingState.earningsDetected => AppColors.primary,
  BookingState.recorded => AppColors.green,
  BookingState.bookingEnded => AppColors.textSecondary,
  BookingState.errorRequiresReview => AppColors.orange,
};

IconData paymentIcon(String? method) {
  final value = (method ?? '').toLowerCase();
  if (value.contains('cash')) return Icons.payments_outlined;
  if (value.contains('card')) return Icons.credit_card;
  if (value.contains('wallet') ||
      value.contains('gcash') ||
      value.contains('maya')) {
    return Icons.account_balance_wallet_outlined;
  }
  return Icons.receipt_long_outlined;
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.onTip,
    this.showDay = false,
  });

  final BookingTransaction transaction;
  final VoidCallback? onTap;
  final VoidCallback? onTip;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final statusColor = bookingStateColor(transaction.bookingStatus);
    final pending = !transaction.hasPlatformEarnings;
    final timeLabel = showDay
        ? '${Dates.relativeLabel(transaction.createdAt)} • ${Dates.time.format(transaction.createdAt)}'
        : Dates.time.format(transaction.createdAt);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              paymentIcon(transaction.paymentMethod),
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        transaction.paymentMethod ?? 'Awaiting details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (transaction.detectionSource == DetectionSource.ocr)
                      const Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: AppColors.primary,
                      ),
                    if (transaction.isManuallyEdited)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$timeLabel  •  ${transaction.bookingReference}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 5),
                StatusPill(
                  label: transaction.bookingStatus.label,
                  color: statusColor,
                  compact: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pending ? '—' : Money.format(transaction.recordedEarningsCents),
                style: TextStyle(
                  color: pending ? AppColors.textMuted : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                transaction.fareToCollectCents == null
                    ? (pending ? 'Waiting for earnings' : 'Fare —')
                    : 'Fare ${Money.format(transaction.fareToCollectCents!)}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
              if (transaction.effectiveTipCents > 0)
                Text(
                  '+${Money.format(transaction.effectiveTipCents)} tip',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (onTip != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add tip',
              onPressed: onTip,
              icon: const Icon(
                Icons.add_circle_outline,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
