import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Offline-first SQLite storage for SIMOVE.
class AppDatabase {
  AppDatabase({this.databaseName = 'simove.db'});

  final String databaseName;
  Database? _db;
  static const int schemaVersion = 1;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Database has not been opened yet.');
    }
    return database;
  }

  Future<Database> open() async {
    if (_db != null) return _db!;
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, databaseName);
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        booking_reference TEXT NOT NULL UNIQUE,
        booking_status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        platform_earnings_cents INTEGER,
        fare_to_collect_cents INTEGER,
        payment_method TEXT,
        tip_cents INTEGER NOT NULL DEFAULT 0,
        tip_type TEXT NOT NULL DEFAULT 'cash',
        tip_included_in_platform_earnings INTEGER NOT NULL DEFAULT 0,
        detection_source TEXT NOT NULL DEFAULT 'manual',
        detection_confidence REAL,
        notes TEXT,
        screen_signature TEXT,
        booking_fingerprint TEXT,
        earnings_detected_at INTEGER,
        ended_at INTEGER,
        manually_edited INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_transactions_created_at ON transactions(created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_status ON transactions(booking_status)',
    );
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_expenses_created_at ON expenses(created_at)',
    );
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        setting_key TEXT NOT NULL UNIQUE,
        setting_value TEXT
      )
    ''');
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Migrations are applied incrementally so existing earning history is
    // preserved across app updates.
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        // case 2:
        //   await db.execute('ALTER TABLE transactions ADD COLUMN ...');
        //   break;
        default:
          break;
      }
    }
  }
}
