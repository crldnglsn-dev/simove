// Dev-only helper: dumps a pulled SIMOVE database to stdout.
// ignore_for_file: avoid_print

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(args.first);
  final tx = await db.query('transactions');
  print('transactions: ${tx.length}');
  for (final row in tx) {
    print(row);
  }
  final expenses = await db.query('expenses');
  print('expenses: ${expenses.length}');
  await db.close();
}
