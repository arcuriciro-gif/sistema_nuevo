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

  /// Cantidad de documentos de venta (remitos + facturas/NE/CI, sin presupuestos).
  Future<int> cantidadDocumentosVenta() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM (
        SELECT id FROM remitos WHERE estado != 'anulado'
        UNION ALL
        SELECT id FROM ventas
        WHERE estado != 'anulada' AND tipo NOT IN ('presupuesto')
      )
    ''');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Listado unificado ordenado por fecha (más reciente primero).
  Future<List<Map<String, dynamic>>> listarDocumentosVenta() async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT
        origen,
        id,
        numero,
        fecha,
        total,
        estado,
        tipo,
        tipoLabel,
        clienteId,
        clienteNombre,
        ordenFecha
      FROM (
        SELECT
          'remito' AS origen,
          r.id AS id,
          r.numero AS numero,
          r.fecha AS fecha,
          r.total AS total,
          r.estado AS estado,
          'remito' AS tipo,
          'Remito' AS tipoLabel,
          r.clienteId AS clienteId,
          c.nombre AS clienteNombre,
          COALESCE(r.fechaCreacion, r.fecha) AS ordenFecha
        FROM remitos r
        LEFT JOIN clientes c ON c.id = r.clienteId
        WHERE r.estado != 'anulado'
        UNION ALL
        SELECT
          'venta' AS origen,
          v.id AS id,
          v.numero AS numero,
          v.fecha AS fecha,
          v.total AS total,
          v.estado AS estado,
          v.tipo AS tipo,
          CASE v.tipo
            WHEN 'factura_a' THEN 'Factura A'
            WHEN 'factura_b' THEN 'Factura B'
            WHEN 'factura_c' THEN 'Factura C'
            WHEN 'nota_entrega' THEN 'Nota de entrega'
            WHEN 'comprobante_interno' THEN 'Comprobante interno'
            WHEN 'remito' THEN 'Remito'
            ELSE v.tipo
          END AS tipoLabel,
          v.clienteId AS clienteId,
          c.nombre AS clienteNombre,
          COALESCE(v.fechaCreacion, v.fecha) AS ordenFecha
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.estado != 'anulada' AND v.tipo NOT IN ('presupuesto')
      )
      ORDER BY datetime(ordenFecha) DESC, id DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> topProductos({int limite = 5}) async {
    final db = await _dbHelper.database;
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
        WHERE r.estado != 'anulado'
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
        WHERE v.estado != 'anulada'
          AND v.tipo NOT IN ('presupuesto')
      )
      GROUP BY productoId
      ORDER BY totalVendido DESC
      LIMIT ?
    ''', [limite]);
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
