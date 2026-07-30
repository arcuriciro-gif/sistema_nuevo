import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../domain/domain_event.dart';

/// Migración: productos históricos sin filas en `inventory_ledger`.
///
/// Inserta un snapshot idempotente:
/// `stock_before=0`, `delta=stock_actual`, `stock_after=stock_actual`
/// **sin** mutar `productos.stock` y **sin** encolar stock_ops cloud.
///
/// Así G4/G7 valen: `Proj = base + Σδ` con base=0.
class LegacyLedgerMigration {
  LegacyLedgerMigration._();
  static final LegacyLedgerMigration instance = LegacyLedgerMigration._();

  static String seedEventId(int productoId) =>
      'inv:ajuste:legacy_seed:$productoId';

  /// Cuántos productos activos aún no tienen ledger.
  Future<int> countMissing() async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery('''
SELECT COUNT(*) c FROM productos p
WHERE (p.deleted_at IS NULL OR p.deleted_at = '')
  AND NOT EXISTS (
    SELECT 1 FROM inventory_ledger l WHERE l.product_id = p.id
  )
''');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Backfill por lotes. Idempotente por event_id estable.
  /// Retorna cuántos productos recibieron seed en esta corrida.
  Future<int> seedMissing({int limit = 500}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
SELECT p.id, p.codigo, p.stock FROM productos p
WHERE (p.deleted_at IS NULL OR p.deleted_at = '')
  AND NOT EXISTS (
    SELECT 1 FROM inventory_ledger l WHERE l.product_id = p.id
  )
ORDER BY p.id ASC
LIMIT ?
''', [limit]);

    var n = 0;
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final codigo = row['codigo']?.toString();
      final stock = (row['stock'] as num?)?.toInt() ?? 0;
      final ok = await db.transaction((txn) async {
        return seedOneInTxn(
          txn,
          productoId: id,
          codigo: codigo,
          stockActual: stock,
        );
      });
      if (ok) n++;
    }
    if (n > 0) {
      debugPrint('LegacyLedgerMigration: seeded $n productos');
    }
    return n;
  }

  /// Corre lotes hasta `countMissing == 0` o tope de batches.
  /// Cierra el residual de campo (~2861 sin ledger) en un arranque.
  Future<int> seedUntilDone({
    int batchSize = 500,
    int maxBatches = 30,
  }) async {
    var total = 0;
    for (var i = 0; i < maxBatches; i++) {
      final missing = await countMissing();
      if (missing == 0) break;
      final n = await seedMissing(limit: batchSize);
      total += n;
      if (n == 0) break;
    }
    if (total > 0) {
      debugPrint('LegacyLedgerMigration: seedUntilDone total=$total');
    }
    return total;
  }

  /// Inserta snapshot ledger sin tocar proyección.
  Future<bool> seedOneInTxn(
    DatabaseExecutor txn, {
    required int productoId,
    required String? codigo,
    required int stockActual,
  }) async {
    final eventId = seedEventId(productoId);
    final existing = await txn.query(
      'domain_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: [eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    final ledgerExisting = await txn.query(
      'inventory_ledger',
      columns: ['id'],
      where: 'product_id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    if (ledgerExisting.isNotEmpty) return false;

    final now = DateTime.now().toUtc();
    final event = DomainEvent(
      eventId: eventId,
      type: DomainEventType.ajusteInventario,
      aggregateType: 'producto',
      aggregateId: '$productoId',
      createdBy: 'legacy_migration',
      createdAt: now,
      payload: {
        'tipo': stockActual >= 0 ? 'entrada' : 'salida',
        'motivo': 'legacy_seed_from_projection',
        'documentType': 'legacy_seed',
        'documentId': '$productoId',
        'lines': [
          InventoryLine(
            productoId: productoId,
            cantidad: stockActual.abs(),
            productoCodigo: codigo,
          ).toJson(),
        ],
      },
    );
    await txn.insert('domain_events', event.toRow());
    await txn.insert('inventory_ledger', {
      'event_id': '$eventId:$productoId',
      'parent_event_id': eventId,
      'product_id': productoId,
      'product_codigo': codigo,
      'delta': stockActual,
      'reason': 'legacy_seed_from_projection',
      'document_type': 'legacy_seed',
      'document_id': '$productoId',
      'stock_before': 0,
      'stock_after': stockActual,
      'created_at': now.toIso8601String(),
    });
    return true;
  }
}
