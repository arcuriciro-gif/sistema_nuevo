import 'dart:convert';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/movimiento_stock.dart';
import '../models/producto.dart';
import 'alertas_stock_service.dart';
import 'auth_service.dart';

class StockService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> obtenerMovimientos({int? productoId}) async {
    final db = await dbHelper.database;
    return db.rawQuery(
      '''
      SELECT m.*, p.descripcion AS productoNombre, p.codigo AS productoCodigo, p.stock AS stockActual
      FROM movimientos_stock m
      JOIN productos p ON p.id = m.productoId
      ${productoId != null ? 'WHERE m.productoId = ?' : ''}
      ORDER BY datetime(m.fecha) DESC, m.id DESC
      ''',
      productoId != null ? [productoId] : [],
    );
  }

  Future<int> registrarMovimiento(MovimientoStock movimiento) async {
    final db = await dbHelper.database;

    final movimientoId = await db.transaction((txn) async {
      final productoRows = await txn.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [movimiento.productoId],
        limit: 1,
      );
      final stockAnterior =
          (productoRows.isNotEmpty ? productoRows.first['stock'] as num? : 0)
                  ?.toInt() ??
              0;
      final multiplicador = movimiento.tipo == 'salida' ? -1 : 1;
      final stockNuevo = stockAnterior + (movimiento.cantidad * multiplicador);
      final movimientoCompleto = movimiento.copyWith(
        usuario: movimiento.usuario.isNotEmpty
            ? movimiento.usuario
            : (AuthService.instance.currentUser?.usuario ?? 'sistema'),
        stockAnterior: stockAnterior,
        stockNuevo: stockNuevo,
      );

      final movimientoId = await txn.insert(
        'movimientos_stock',
        movimientoCompleto.toMap()..remove('id'),
      );

      await txn.rawUpdate(
        'UPDATE productos SET stock = stock + ? WHERE id = ?',
        [movimiento.cantidad * multiplicador, movimiento.productoId],
      );

      await AuthService.instance.registrarCambio(
        'AJUSTE_STOCK',
        'movimientos_stock',
        'Movimiento ${movimiento.tipo} de ${movimiento.cantidad} unidades (producto ${movimiento.productoId})',
        valorAnterior: jsonEncode({'stock': stockAnterior}),
        valorNuevo: jsonEncode({'stock': stockNuevo}),
      );

      return movimientoId;
    });

    await FirestoreSyncService.instance
        .subirProductoPorId(movimiento.productoId);
    DataRefreshHub.instance.notifyStock();
    try {
      await AlertasStockService.instance.evaluarProducto(movimiento.productoId);
    } catch (_) {}
    return movimientoId;
  }

  Future<List<Producto>> obtenerProductosConStockBajo({int limite = 5}) async {
    final db = await dbHelper.database;
    final resultado = await db.rawQuery(
      '''
SELECT * FROM productos
WHERE (stock_minimo > 0 AND stock <= stock_minimo)
   OR (stock_minimo = 0 AND stock <= ?)
ORDER BY stock ASC, descripcion
''',
      [limite],
    );

    return resultado.map((e) => Producto.fromMap(e)).toList();
  }
}
