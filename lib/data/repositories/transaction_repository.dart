import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/booking_transaction.dart';

class TransactionRepository {
  TransactionRepository(this._database);

  final AppDatabase _database;
  final DateFormat _referenceDay = DateFormat('yyyyMMdd');

  Database get _db => _database.db;

  Future<BookingTransaction> insert(BookingTransaction transaction) async {
    final map = transaction.toDbMap()..remove('id');
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('transactions', map);
    });
    return transaction.copyWith(id: id);
  }

  Future<BookingTransaction> createPending({
    DetectionSource source = DetectionSource.ocr,
    String? signature,
    double? confidence,
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now();
    var sequence = await countForDay(now) + 1;
    var reference = _buildReference(now, sequence);
    while (await referenceExists(reference)) {
      sequence++;
      reference = _buildReference(now, sequence);
    }
    return insert(
      BookingTransaction(
        bookingReference: reference,
        bookingStatus: BookingState.bookingDetected,
        createdAt: now,
        updatedAt: now,
        detectionSource: source,
        screenSignature: signature,
        detectionConfidence: confidence,
      ),
    );
  }

  /// Inserts a transaction produced by the detection engine, assigning the
  /// next human-readable booking reference for that day.
  Future<BookingTransaction> insertDetected(BookingTransaction draft) async {
    final day = draft.createdAt;
    var sequence = await countForDay(day) + 1;
    var reference = _buildReference(day, sequence);
    while (await referenceExists(reference)) {
      sequence++;
      reference = _buildReference(day, sequence);
    }
    return insert(
      BookingTransaction(
        bookingReference: reference,
        bookingStatus: draft.bookingStatus,
        createdAt: draft.createdAt,
        updatedAt: draft.updatedAt,
        platformEarningsCents: draft.platformEarningsCents,
        fareToCollectCents: draft.fareToCollectCents,
        paymentMethod: draft.paymentMethod,
        tipCents: draft.tipCents,
        tipType: draft.tipType,
        tipIncludedInPlatformEarnings: draft.tipIncludedInPlatformEarnings,
        detectionSource: draft.detectionSource,
        detectionConfidence: draft.detectionConfidence,
        notes: draft.notes,
        screenSignature: draft.screenSignature,
        bookingFingerprint: draft.bookingFingerprint,
        earningsDetectedAt: draft.earningsDetectedAt,
        endedAt: draft.endedAt,
        isManuallyEdited: draft.isManuallyEdited,
      ),
    );
  }

  String _buildReference(DateTime day, int sequence) {
    return 'SMV-${_referenceDay.format(day)}-${sequence.toString().padLeft(3, '0')}';
  }

  Future<bool> referenceExists(String reference) async {
    final result = await _db.query(
      'transactions',
      columns: ['id'],
      where: 'booking_reference = ?',
      whereArgs: [reference],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> countForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final result = await _db.rawQuery(
      'SELECT COUNT(*) FROM transactions WHERE created_at >= ? AND created_at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<BookingTransaction?> getById(int id) async {
    final rows = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookingTransaction.fromDbMap(rows.first);
  }

  Future<List<BookingTransaction>> between(
    DateTime start,
    DateTime end, {
    int? limit,
  }) async {
    final rows = await _db.query(
      'transactions',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(BookingTransaction.fromDbMap).toList();
  }

  Future<List<BookingTransaction>> recent({int limit = 50}) async {
    final rows = await _db.query(
      'transactions',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(BookingTransaction.fromDbMap).toList();
  }

  /// The newest transaction that has not been explicitly closed.
  Future<BookingTransaction?> latestActive() async {
    final rows = await _db.query(
      'transactions',
      where:
          'booking_status NOT IN (?, ?) AND ended_at IS NULL',
      whereArgs: [
        BookingState.bookingEnded.dbValue,
        BookingState.idle.dbValue,
      ],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookingTransaction.fromDbMap(rows.first);
  }

  Future<BookingTransaction> update(BookingTransaction transaction) async {
    final id = transaction.id;
    if (id == null) {
      throw ArgumentError('Cannot update a transaction without an id.');
    }
    final map = transaction.toDbMap()
      ..remove('id')
      ..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transactions',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
    final updated = await getById(id);
    if (updated == null) {
      throw StateError('Transaction $id disappeared during update.');
    }
    return updated;
  }

  Future<void> delete(int id) async {
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    await _db.delete('transactions');
  }

  Future<int> totalCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) FROM transactions');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
