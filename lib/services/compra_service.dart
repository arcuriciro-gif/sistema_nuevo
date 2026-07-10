import 'package:sqflite/sqflite.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../database/database_helper.dart';
import '../models/compra.dart';
import '../models/compra_detalle.dart';
import '../models/movimiento_stock.dart';
import 'auth_service.dart';

class CompraService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<String> generarNumero() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero,3) AS INTEGER)) AS maxN FROM compras WHERE numero LIKE 'C-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    return 'C-${(maxN + 1).toString().padLeft(5, '0')}';
  }

  Future<int> insertar(Compra compra, List<CompraDetalle> items) async {
    final db = await dbHelper.database;

    final compraId = await db.transaction((txn) async {
      final compraId = await txn.insert('compras', {
        'proveedorId': compra.proveedorId,
        'proveedorNombre': compra.proveedorNombre,
        'numero': compra.numero,
        'factura': compra.factura,
        'fecha': compra.fecha.toIso8601String(),
        'total': compra.total,
        'descuento': compra.descuento,
        'iva': compra.iva,
        'observaciones': compra.observaciones,
        'fechaCreacion': DateTime.now().toIso8601String(),
        'estado': compra.estado,
      });

      for (final item in items) {
        await txn.insert('compra_items', {
          'compraId': compraId,
          'productoId': item.productoId,
          'productoDescripcion': item.productoDescripcion,
          'cantidad': item.cantidad,
          'costo': item.costo,
          'subtotal': item.subtotal,
        });

        final productoRows = await txn.query(
          'productos',
          columns: ['costo', 'precio', 'stock'],
          where: 'id = ?',
          whereArgs: [item.productoId],
          limit: 1,
        );
        final costoAnterior =
            (productoRows.isNotEmpty ? productoRows.first['costo'] as num? : 0)
                    ?.toDouble() ??
                0;
        final precioAnterior =
            (productoRows.isNotEmpty ? productoRows.first['precio'] as num? : 0)
                    ?.toDouble() ??
                0;
        final stockAnterior =
            (productoRows.isNotEmpty ? productoRows.first['stock'] as num? : 0)
                    ?.toInt() ??
                0;
        final stockNuevo = stockAnterior + item.cantidad;

        await txn.rawUpdate(
          'UPDATE productos SET stock = stock + ?, costo = ? WHERE id = ?',
          [item.cantidad, item.costo, item.productoId],
        );

        if (costoAnterior != item.costo) {
          final variacion = costoAnterior > 0
              ? ((item.costo - costoAnterior) / costoAnterior) * 100
              : 0.0;
          await txn.insert('historial_precios', {
            'productoId': item.productoId,
            'fecha': DateTime.now().toIso8601String(),
            'usuario': AuthService.instance.currentUser?.usuario ?? 'sistema',
            'costoAnterior': costoAnterior,
            'costoNuevo': item.costo,
            'precioAnterior': precioAnterior,
            'precioNuevo': precioAnterior,
            'porcentaje': variacion,
            'listaModificada': 'Costo',
            'motivo': 'Compra ${compra.numero}',
          });
        }

        final movimiento = MovimientoStock(
          productoId: item.productoId,
          tipo: 'entrada',
          cantidad: item.cantidad,
          fecha: DateTime.now(),
          remitoId: compraId.toString(),
          motivo: 'Entrada por compra ${compra.numero}',
          usuario: AuthService.instance.currentUser?.usuario ?? 'sistema',
          stockAnterior: stockAnterior,
          stockNuevo: stockNuevo,
        );

        await txn.insert(
          'movimientos_stock',
          movimiento.toMap()..remove('id'),
        );
      }

      return compraId;
    });

    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'compra',
      id: compraId,
      upload: () => FirestoreSyncService.instance.subirCompra(compraId),
    );
    DataRefreshHub.instance.notifyTodo();
    return compraId;
  }

  Future<List<Map<String, dynamic>>> obtenerTodasConProveedor() async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT c.*, p.nombre AS proveedorNombreActual
      FROM compras c
      LEFT JOIN proveedores p ON p.id = c.proveedorId
      ORDER BY datetime(c.fecha) DESC, datetime(c.fechaCreacion) DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> obtenerItems(int compraId) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT ci.*, p.codigo, p.marca
      FROM compra_items ci
      LEFT JOIN productos p ON p.id = ci.productoId
      WHERE ci.compraId = ?
    ''', [compraId]);
  }

  Future<void> anular(int id) async {
    final db = await dbHelper.database;

    await db.transaction((txn) async {
      final compras = await txn.query(
        'compras',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (compras.isEmpty) return;

      final compra = compras.first;
      if (compra['estado'] == 'anulada') return;

      final items = await txn.query(
        'compra_items',
        where: 'compraId = ?',
        whereArgs: [id],
      );

      for (final item in items) {
        final productoId = item['productoId'] as int;
        final cantidad = item['cantidad'] as int? ?? 0;
        final productoRows = await txn.query(
          'productos',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [productoId],
          limit: 1,
        );
        final stockAnterior =
            (productoRows.isNotEmpty ? productoRows.first['stock'] as num? : 0)
                    ?.toInt() ??
                0;
        final stockNuevo = stockAnterior - cantidad;

        await txn.rawUpdate(
          'UPDATE productos SET stock = stock - ? WHERE id = ?',
          [cantidad, productoId],
        );

        final movimiento = MovimientoStock(
          productoId: productoId,
          tipo: 'reversion',
          cantidad: cantidad,
          fecha: DateTime.now(),
          remitoId: id.toString(),
          motivo: 'Reversión de compra ${compra['numero']}',
          usuario: AuthService.instance.currentUser?.usuario ?? 'sistema',
          stockAnterior: stockAnterior,
          stockNuevo: stockNuevo,
        );

        await txn.insert(
          'movimientos_stock',
          movimiento.toMap()..remove('id'),
        );
      }

      await txn.update(
        'compras',
        {'estado': 'anulada'},
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'compra',
      id: id,
      upload: () => FirestoreSyncService.instance.subirCompra(id),
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<int> cantidad() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery('SELECT COUNT(*) total FROM compras');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> totalCompras() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM compras WHERE estado != 'anulada'",
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> totalComprasPorPeriodo(DateTime desde, DateTime hasta) async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM compras WHERE estado != 'anulada' AND fecha >= ? AND fecha <= ?",
      [desde.toIso8601String(), hasta.toIso8601String()],
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> comprasPorMes({int meses = 6}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT strftime('%Y-%m', fecha) AS mes, SUM(total) AS total
      FROM compras
      WHERE estado != 'anulada'
      AND fecha >= date('now', '-$meses months')
      GROUP BY strftime('%Y-%m', fecha)
      ORDER BY mes ASC
    ''');
  }
}
