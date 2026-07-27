import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Hold-set para stock_ops que no se pueden aplicar aún.
///
/// Permite avanzar el watermark sin perder la op (anti-HOL):
/// la op queda registrada y un sweeper la reintenta aparte.
class StockOpsPullHoldStore {
  StockOpsPullHoldStore._();
  static final StockOpsPullHoldStore instance = StockOpsPullHoldStore._();

  static const reasonPendingApply = 'pending_apply';
  static const reasonMissingProduct = 'missing_product';

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<void> upsert({
    required String opId,
    required String reason,
    String? codigo,
    int? delta,
    String? at,
  }) async {
    if (opId.isEmpty) return;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final db = await _db;
    final existing = await db.query(
      'stock_ops_pull_holds',
      columns: ['attempts', 'first_seen_at'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('stock_ops_pull_holds', {
        'op_id': opId,
        'reason': reason,
        'codigo': codigo,
        'delta': delta,
        'op_at': at,
        'first_seen_at': ahora,
        'retry_after': ahora,
        'attempts': 0,
        'updated_at': ahora,
      });
      return;
    }
    final attempts = (existing.first['attempts'] as num?)?.toInt() ?? 0;
    await db.update(
      'stock_ops_pull_holds',
      {
        'reason': reason,
        'codigo': codigo ?? existing.first['codigo'],
        'delta': delta,
        'op_at': at,
        'attempts': attempts + 1,
        'retry_after': DateTime.now()
            .toUtc()
            .add(Duration(seconds: (30 * (attempts + 1)).clamp(30, 600)))
            .toIso8601String(),
        'updated_at': ahora,
      },
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<void> remove(String opId) async {
    if (opId.isEmpty) return;
    await (await _db).delete(
      'stock_ops_pull_holds',
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<bool> contains(String opId) async {
    if (opId.isEmpty) return false;
    final rows = await (await _db).query(
      'stock_ops_pull_holds',
      columns: ['op_id'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> listDue({int limit = 40}) async {
    final ahora = DateTime.now().toUtc().toIso8601String();
    return (await _db).query(
      'stock_ops_pull_holds',
      where: 'retry_after IS NULL OR retry_after <= ?',
      whereArgs: [ahora],
      orderBy: 'first_seen_at ASC',
      limit: limit,
    );
  }

  Future<int> count() async {
    final r = await (await _db).rawQuery(
      'SELECT COUNT(*) c FROM stock_ops_pull_holds',
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }
}
