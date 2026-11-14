import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../data/models/booking_transaction.dart';
import '../data/models/expense.dart';

class EarningsExporter {
  EarningsExporter._();

  static Future<void> shareCsv({
    required List<BookingTransaction> transactions,
    required List<Expense> expenses,
  }) async {
    final now = DateTime.now();
    final buffer = StringBuffer();
    buffer.writeln(
      'Type,Reference,Date,Platform Earnings,Fare To Collect,Payment Method,Tip,Tip Type,Recorded Earnings,Status,Source,Confidence,Notes',
    );
    for (final t in transactions) {
      buffer.writeln(
        [
          'Booking',
          t.bookingReference,
          Dates.fullDate.format(t.createdAt),
          Money.forCsv(t.platformEarningsCents),
          Money.forCsv(t.fareToCollectCents),
          _csv(t.paymentMethod ?? ''),
          Money.forCsv(t.effectiveTipCents),
          t.tipType.name,
          Money.forCsv(t.hasPlatformEarnings ? t.recordedEarningsCents : null),
          t.bookingStatus.label,
          t.detectionSource.label,
          t.detectionConfidence?.toStringAsFixed(2) ?? '',
          _csv(t.notes ?? ''),
        ].join(','),
      );
    }
    buffer.writeln();
    buffer.writeln('Type,Category,Date,Amount,Description');
    for (final e in expenses) {
      buffer.writeln(
        [
          'Expense',
          e.category,
          Dates.fullDate.format(e.createdAt),
          Money.forCsv(e.amountCents),
          _csv(e.description ?? ''),
        ].join(','),
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/simove_export_${Dates.fileStamp.format(now)}.csv',
    );
    await file.writeAsString(buffer.toString());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'SIMOVE earnings export',
        text: 'SIMOVE earnings export — ${Dates.dateOnly.format(now)}',
      ),
    );
  }

  static Future<void> shareJson({
    required List<BookingTransaction> transactions,
    required List<Expense> expenses,
  }) async {
    final now = DateTime.now();
    final payload = {
      'app': 'SIMOVE',
      'exportedAt': now.toIso8601String(),
      'currency': Money.code,
      'transactions': [
        for (final t in transactions)
          {
            'reference': t.bookingReference,
            'createdAt': t.createdAt.toIso8601String(),
            'status': t.bookingStatus.name,
            'platformEarnings': t.platformEarningsCents,
            'fareToCollect': t.fareToCollectCents,
            'paymentMethod': t.paymentMethod,
            'tip': t.tipCents,
            'tipType': t.tipType.name,
            'tipIncludedInPlatformEarnings': t.tipIncludedInPlatformEarnings,
            'recordedEarnings': t.recordedEarningsCents,
            'detectionSource': t.detectionSource.name,
            'detectionConfidence': t.detectionConfidence,
            'notes': t.notes,
          },
      ],
      'expenses': [
        for (final e in expenses)
          {
            'category': e.category,
            'amount': e.amountCents,
            'description': e.description,
            'createdAt': e.createdAt.toIso8601String(),
          },
      ],
    };
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/simove_backup_${Dates.fileStamp.format(now)}.json',
    );
    await file.writeAsString(_prettyJson(payload));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'SIMOVE backup',
        text: 'SIMOVE local backup',
      ),
    );
  }

  static String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _prettyJson(Object? value) {
    // A tiny dependency-free pretty printer keeps the backup readable.
    const indent = '  ';
    String encode(Object? node, int depth) {
      final pad = indent * depth;
      final childPad = indent * (depth + 1);
      if (node is Map) {
        if (node.isEmpty) return '{}';
        final entries = node.entries
            .map((e) => '$childPad"${e.key}": ${encode(e.value, depth + 1)}')
            .join(',\n');
        return '{\n$entries\n$pad}';
      }
      if (node is List) {
        if (node.isEmpty) return '[]';
        final items = node
            .map((e) => '$childPad${encode(e, depth + 1)}')
            .join(',\n');
        return '[\n$items\n$pad]';
      }
      if (node is String) {
        return '"${node.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
      }
      return '$node';
    }

    return encode(value, 0);
  }
}
