import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Fila de divergencia stock proyección vs ledger.
class StockValidationIssue {
  StockValidationIssue({
    required this.productoId,
    required this.codigo,
    required this.stockProyectado,
    required this.stockDesdeLedger,
    required this.diferencia,
    required this.ledgerLines,
    required this.primerEventId,
    required this.ultimoEventId,
  });

  final int productoId;
  final String codigo;
  final int stockProyectado;
  final int stockDesdeLedger;
  final int diferencia;
  final int ledgerLines;
  final String? primerEventId;
  final String? ultimoEventId;

  Map<String, dynamic> toJson() => {
        'productoId': productoId,
        'codigo': codigo,
        'stockProyectado': stockProyectado,
        'stockDesdeLedger': stockDesdeLedger,
        'diferencia': diferencia,
        'ledgerLines': ledgerLines,
        'primerEventId': primerEventId,
        'ultimoEventId': ultimoEventId,
      };
}

/// Validador forense: para cada producto
/// `stock == stock_inicial_ledger + SUM(delta)`.
///
/// Si hay diferencia de 1 unidad, reporta event_ids del historial.
class StockIntegrityValidator {
  StockIntegrityValidator._();
  static final StockIntegrityValidator instance = StockIntegrityValidator._();

  Future<List<StockValidationIssue>> validateAll({
    bool repairProjection = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final productos = await db.query(
      'productos',
      columns: ['id', 'codigo', 'stock'],
      where: "deleted_at IS NULL OR deleted_at = ''",
    );
    final issues = <StockValidationIssue>[];
    for (final p in productos) {
      final id = (p['id'] as num?)?.toInt();
      if (id == null) continue;
      final issue = await validateProducto(db, id, codigo: p['codigo']?.toString());
      if (issue == null) continue;
      issues.add(issue);
      if (repairProjection) {
        // Reparación explícita vía ledger event (no silent UPDATE).
        // Aquí solo reportamos; repair se hace con DomainEvent ajuste.
      }
    }
    return issues;
  }

  Future<StockValidationIssue?> validateProducto(
    DatabaseExecutor db,
    int productoId, {
    String? codigo,
  }) async {
    final prod = await db.query(
      'productos',
      columns: ['id', 'codigo', 'stock'],
      where: 'id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    if (prod.isEmpty) return null;
    final cod = codigo ?? prod.first['codigo']?.toString() ?? '';
    final proyectado = (prod.first['stock'] as num?)?.toInt() ?? 0;

    final sum = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) s, COUNT(*) c FROM inventory_ledger '
      'WHERE product_id = ?',
      [productoId],
    );
    final sumDelta = (sum.first['s'] as num?)?.toInt() ?? 0;
    final lines = (sum.first['c'] as num?)?.toInt() ?? 0;

    // Stock inicial = stock_before de la primera línea (si existe).
    int stockInicial = 0;
    String? firstId;
    String? lastId;
    if (lines > 0) {
      final first = await db.query(
        'inventory_ledger',
        columns: ['event_id', 'stock_before'],
        where: 'product_id = ?',
        whereArgs: [productoId],
        orderBy: 'id ASC',
        limit: 1,
      );
      final last = await db.query(
        'inventory_ledger',
        columns: ['event_id'],
        where: 'product_id = ?',
        whereArgs: [productoId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (first.isNotEmpty) {
        stockInicial = (first.first['stock_before'] as num?)?.toInt() ?? 0;
        firstId = first.first['event_id']?.toString();
      }
      if (last.isNotEmpty) {
        lastId = last.first['event_id']?.toString();
      }
    } else {
      // Sin ledger: proyección es la autoridad residual (legado).
      return null;
    }

    final esperado = stockInicial + sumDelta;
    if (esperado == proyectado) return null;
    return StockValidationIssue(
      productoId: productoId,
      codigo: cod,
      stockProyectado: proyectado,
      stockDesdeLedger: esperado,
      diferencia: proyectado - esperado,
      ledgerLines: lines,
      primerEventId: firstId,
      ultimoEventId: lastId,
    );
  }
}
