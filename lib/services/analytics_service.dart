import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/producto.dart';

/// Estadísticas unificadas (remitos + ventas) con ganancia real snapshotteada.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<double> gananciaReal({DateTime? desde, DateTime? hasta}) async {
    final db = await _dbHelper.database;
    final filtrosRemito = <String>["r.estado != 'anulado'"];
    final filtrosVenta = <String>["v.estado != 'anulada'", "v.tipo NOT IN ('presupuesto')"];
    final args = <Object?>[];

    if (desde != null) {
      filtrosRemito.add('r.fecha >= ?');
      filtrosVenta.add('v.fecha >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      filtrosRemito.add('r.fecha <= ?');
      filtrosVenta.add('v.fecha <= ?');
      args.add(hasta.toIso8601String());
    }

    final whereR = filtrosRemito.join(' AND ');
    final whereV = filtrosVenta.join(' AND ');
    // args se duplican para ambas subconsultas
    final allArgs = [...args, ...args];

    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(g), 0) AS ganancia FROM (
        SELECT COALESCE(ri.ganancia,
          (ri.subtotal - (ri.cantidad * COALESCE(ri.costoUnitario, 0)))) AS g
        FROM remito_items ri
        JOIN remitos r ON r.id = ri.remitoId
        WHERE $whereR
        UNION ALL
        SELECT COALESCE(vi.ganancia,
          (vi.subtotal - (vi.cantidad * COALESCE(vi.costoUnitario, 0)))) AS g
        FROM ventas_items vi
        JOIN ventas v ON v.id = vi.ventaId
        WHERE $whereV
      )
    ''', allArgs);

    return (rows.first['ganancia'] as num?)?.toDouble() ?? 0;
  }

  Future<double> ventasTotales({DateTime? desde, DateTime? hasta}) async {
    final db = await _dbHelper.database;
    final filtrosR = <String>["estado != 'anulado'"];
    final filtrosV = <String>["estado != 'anulada'", "tipo NOT IN ('presupuesto')"];
    final args = <Object?>[];
    if (desde != null) {
      filtrosR.add('fecha >= ?');
      filtrosV.add('fecha >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      filtrosR.add('fecha <= ?');
      filtrosV.add('fecha <= ?');
      args.add(hasta.toIso8601String());
    }
    final whereR = filtrosR.join(' AND ');
    final whereV = filtrosV.join(' AND ');
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(t), 0) AS total FROM (
        SELECT total AS t FROM remitos WHERE $whereR
        UNION ALL
        SELECT total AS t FROM ventas WHERE $whereV
      )
    ''', [...args, ...args]);
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> topProductos({
    int limite = 5,
    DateTime? desde,
    DateTime? hasta,
    bool ascendente = false,
  }) async {
    final db = await _dbHelper.database;
    final filtrosR = <String>["r.estado != 'anulado'"];
    final filtrosV = <String>["v.estado != 'anulada'", "v.tipo NOT IN ('presupuesto')"];
    final args = <Object?>[];
    if (desde != null) {
      filtrosR.add('r.fecha >= ?');
      filtrosV.add('v.fecha >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      filtrosR.add('r.fecha <= ?');
      filtrosV.add('v.fecha <= ?');
      args.add(hasta.toIso8601String());
    }
    final whereR = filtrosR.join(' AND ');
    final whereV = filtrosV.join(' AND ');
    final orden = ascendente ? 'ASC' : 'DESC';
    return db.rawQuery('''
      SELECT
        productoId,
        descripcion,
        SUM(cantidad) AS totalVendido,
        SUM(monto) AS totalMonto,
        SUM(ganancia) AS totalGanancia
      FROM (
        SELECT
          ri.productoId AS productoId,
          p.descripcion AS descripcion,
          ri.cantidad AS cantidad,
          ri.subtotal AS monto,
          COALESCE(ri.ganancia,
            (ri.subtotal - (ri.cantidad * COALESCE(ri.costoUnitario, 0)))) AS ganancia
        FROM remito_items ri
        JOIN productos p ON p.id = ri.productoId
        JOIN remitos r ON r.id = ri.remitoId
        WHERE $whereR
          AND (p.deleted_at IS NULL OR p.deleted_at = '')
        UNION ALL
        SELECT
          vi.productoId,
          COALESCE(vi.productoDescripcion, p.descripcion),
          vi.cantidad,
          vi.subtotal,
          COALESCE(vi.ganancia,
            (vi.subtotal - (vi.cantidad * COALESCE(vi.costoUnitario, 0))))
        FROM ventas_items vi
        LEFT JOIN productos p ON p.id = vi.productoId
        JOIN ventas v ON v.id = vi.ventaId
        WHERE $whereV
      )
      GROUP BY productoId
      ORDER BY totalVendido $orden
      LIMIT ?
    ''', [...args, ...args, limite]);
  }

  Future<List<Map<String, dynamic>>> bottomProductos({
    int limite = 5,
    DateTime? desde,
    DateTime? hasta,
  }) {
    return topProductos(
      limite: limite,
      desde: desde,
      hasta: hasta,
      ascendente: true,
    );
  }

  Future<List<Map<String, dynamic>>> topClientes({int limite = 5}) async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT
        clienteId,
        nombre,
        SUM(cantidadOps) AS cantidadOps,
        SUM(totalCompras) AS totalCompras
      FROM (
        SELECT
          r.clienteId AS clienteId,
          COALESCE(c.nombre, 'Mostrador') AS nombre,
          1 AS cantidadOps,
          r.total AS totalCompras
        FROM remitos r
        LEFT JOIN clientes c ON c.id = r.clienteId
        WHERE r.estado != 'anulado' AND r.clienteId IS NOT NULL
        UNION ALL
        SELECT
          v.clienteId,
          COALESCE(c.nombre, 'Cliente'),
          1,
          v.total
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.estado != 'anulada'
          AND v.tipo NOT IN ('presupuesto')
          AND v.clienteId IS NOT NULL
      )
      GROUP BY clienteId
      ORDER BY totalCompras DESC
      LIMIT ?
    ''', [limite]);
  }

  Future<List<Map<String, dynamic>>> ventasPorMes({int meses = 6}) async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT mes, SUM(total) AS total, SUM(ganancia) AS ganancia FROM (
        SELECT
          strftime('%Y-%m', r.fecha) AS mes,
          r.total AS total,
          COALESCE((
            SELECT SUM(COALESCE(ri.ganancia,
              ri.subtotal - (ri.cantidad * COALESCE(ri.costoUnitario, 0))))
            FROM remito_items ri WHERE ri.remitoId = r.id
          ), 0) AS ganancia
        FROM remitos r
        WHERE r.estado != 'anulado'
          AND r.fecha >= date('now', '-$meses months')
        UNION ALL
        SELECT
          strftime('%Y-%m', v.fecha),
          v.total,
          COALESCE((
            SELECT SUM(COALESCE(vi.ganancia,
              vi.subtotal - (vi.cantidad * COALESCE(vi.costoUnitario, 0))))
            FROM ventas_items vi WHERE vi.ventaId = v.id
          ), 0)
        FROM ventas v
        WHERE v.estado != 'anulada'
          AND v.tipo NOT IN ('presupuesto')
          AND v.fecha >= date('now', '-$meses months')
      )
      GROUP BY mes
      ORDER BY mes ASC
    ''');
  }

  /// Productos con margen sobre precio de venta por debajo del umbral.
  Future<List<Producto>> productosBajoMargen({double umbralPorcentaje = 15}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT * FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
        AND precio > 0
        AND ((precio - costo) / precio) * 100 < ?
      ORDER BY ((precio - costo) / precio) * 100 ASC
      LIMIT 20
    ''', [umbralPorcentaje]);
    return rows.map(Producto.fromMap).toList();
  }

  Future<int> cantidadBajoMargen({double umbralPorcentaje = 15}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
        AND precio > 0
        AND ((precio - costo) / precio) * 100 < ?
    ''', [umbralPorcentaje]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
