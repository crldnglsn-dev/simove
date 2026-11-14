import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  Future<Map<String, String>> loadAll() async {
    final rows = await _db.query('app_settings');
    return {
      for (final row in rows)
        row['setting_key'] as String: (row['setting_value'] as String?) ?? '',
    };
  }

  Future<void> put(String key, String value) async {
    await _db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putAll(Map<String, String> values) async {
    await _db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'app_settings',
          {'setting_key': entry.key, 'setting_value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> remove(String key) async {
    await _db.delete(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> clear() async {
    await _db.delete('app_settings');
  }
}
