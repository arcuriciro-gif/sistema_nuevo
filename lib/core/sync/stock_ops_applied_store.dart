import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Registro durable de stock_ops ya vistas (local-origin o remote-applied).
///
/// Reemplaza el set volátil `_stockOpsHechas` en SharedPreferences (cap 500)
/// que permitía self-echo / re-apply tras rewind.
class StockOpsAppliedStore {
  StockOpsAppliedStore._();
  static final StockOpsAppliedStore instance = StockOpsAppliedStore._();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<bool> contains(String opId) async {
    if (opId.isEmpty) return false;
    final rows = await (await _db).query(
      'stock_ops_applied',
      columns: ['op_id'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> mark({
    required String opId,
    required String origin,
    String? codigo,
    int? delta,
    DatabaseExecutor? txn,
  }) async {
    if (opId.isEmpty) return;
    final exe = txn ?? await _db;
    await exe.insert(
      'stock_ops_applied',
      {
        'op_id': opId,
        'origin': origin,
        'codigo': codigo,
        'delta': delta,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Marca dentro de una TX existente (ledger + outbox atómicos).
  Future<void> markInTxn(
    DatabaseExecutor txn, {
    required String opId,
    required String origin,
    String? codigo,
    int? delta,
  }) =>
      mark(
        opId: opId,
        origin: origin,
        codigo: codigo,
        delta: delta,
        txn: txn,
      );
}
