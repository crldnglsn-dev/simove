import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/expense.dart';

class ExpenseRepository {
  ExpenseRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  Future<Expense> insert(Expense expense) async {
    final id = await _db.insert('expenses', expense.toDbMap()..remove('id'));
    return expense.copyWith(id: id);
  }

  Future<List<Expense>> between(DateTime start, DateTime end) async {
    final rows = await _db.query(
      'expenses',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'created_at DESC',
    );
    return rows.map(Expense.fromDbMap).toList();
  }

  Future<void> delete(int id) async {
    await _db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    await _db.delete('expenses');
  }
}
