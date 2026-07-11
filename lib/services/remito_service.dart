import 'package:sqflite/sqflite.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../database/database_helper.dart';
import '../models/movimiento_stock.dart';
import '../models/remito.dart';
import '../models/remito_detalle.dart';
import 'auth_service.dart';

class RemitoService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<String> generarNumero() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero,3) AS INTEGER)) AS maxN FROM remitos WHERE numero LIKE 'R-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    return 'R-${(maxN + 1).toString().padLeft(5, '0')}';
  }

  Future<int> insertar(Remito remito, List<RemitoDetalle> items) async {
    final db = await dbHelper.database;

    final remitoId = await db.transaction((txn) async {
      final id = await txn.insert(
        'remitos',
        {
          'numero': remito.numero,
          'clienteId': remito.clienteId != null
              ? int.tryParse(remito.clienteId!)
              : null,
          'fecha': remito.fecha.toIso8601String(),
          'total': remito.total,
          'descuento': remito.descuento,
          'estado': remito.estado,
          'estadoPago': remito.estadoPago,
          'totalPagado': 0,
          'saldoPendiente': remito.total,
          'observaciones': remito.observaciones,
          'fechaCreacion': DateTime.now().toIso8601String(),
        },
      );

      for (final item in items) {
        final productoRows = await txn.query(
          'productos',
          columns: ['stock', 'costo'],
          where: 'id = ?',
          whereArgs: [item.productoId],
          limit: 1,
        );
        final stockAnterior =
            (productoRows.isNotEmpty ? productoRows.first['stock'] as num? : 0)
                    ?.toInt() ??
                0;
        final costoUnitario = item.costoUnitario > 0
            ? item.costoUnitario
            : (productoRows.isNotEmpty
                    ? (productoRows.first['costo'] as num?)?.toDouble()
                    : 0) ??
                0;
        final ganancia = item.subtotal - (costoUnitario * item.cantidad);

        await txn.insert('remito_items', {
          'remitoId': id,
          'productoId': item.productoId,
          'cantidad': item.cantidad,
          'precio': item.precioUnitario,
          'subtotal': item.subtotal,
          'costoUnitario': costoUnitario,
          'ganancia': ganancia,
        });

        final stockNuevo = stockAnterior - item.cantidad;

        await txn.rawUpdate(
          'UPDATE productos SET stock = stock - ? WHERE id = ?',
          [item.cantidad, item.productoId],
        );

        final movimiento = MovimientoStock(
          productoId: item.productoId,
          tipo: 'salida',
          cantidad: item.cantidad,
          fecha: DateTime.now(),
          remitoId: id.toString(),
          motivo: 'Salida por remito ${remito.numero}',
          usuario: AuthService.instance.currentUser?.usuario ?? 'sistema',
          stockAnterior: stockAnterior,
          stockNuevo: stockNuevo,
        );

        await txn.insert('movimientos_stock', movimiento.toMap()..remove('id'));
      }

      return id;
    });

    // Sync a Firebase para que PC/celular se actualicen
    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'remito',
      id: remitoId,
      upload: () => FirestoreSyncService.instance.subirRemito(remitoId),
    );
    DataRefreshHub.instance.notifyTodo();
    return remitoId;
  }

  Future<List<Map<String, dynamic>>> obtenerTodosConCliente() async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT
        r.id,
        r.numero,
        r.clienteId,
        r.fecha,
        r.total,
        r.descuento,
        r.estado,
        r.estadoPago,
        r.observaciones,
        r.fechaCreacion,
        c.nombre AS clienteNombre
      FROM remitos r
      LEFT JOIN clientes c ON c.id = r.clienteId
      ORDER BY datetime(r.fecha) DESC, datetime(r.fechaCreacion) DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> obtenerPorCliente(int clienteId) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT
        r.id,
        r.numero,
        r.clienteId,
        r.fecha,
        r.total,
        r.descuento,
        r.estado,
        r.estadoPago,
        r.observaciones,
        r.fechaCreacion,
        c.nombre AS clienteNombre
      FROM remitos r
      LEFT JOIN clientes c ON c.id = r.clienteId
      WHERE r.clienteId = ?
      ORDER BY datetime(r.fecha) DESC, datetime(r.fechaCreacion) DESC
    ''', [clienteId]);
  }

  Future<List<Map<String, dynamic>>> obtenerItems(int remitoId) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT ri.*, p.descripcion, p.codigo, p.marca
      FROM remito_items ri
      JOIN productos p ON p.id = ri.productoId
      WHERE ri.remitoId = ?
    ''', [remitoId]);
  }

  Future<void> actualizarEstadoPago(int id, String estadoPago) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'remitos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final total = (rows.first['total'] as num?)?.toDouble() ?? 0;
    final totalPagado = estadoPago == 'cobrado'
        ? total
        : estadoPago == 'parcial'
            ? total / 2
            : 0.0;
    final saldo = (total - totalPagado).clamp(0, total).toDouble();
    await db.update(
      'remitos',
      {
        'estadoPago': estadoPago,
        'totalPagado': totalPagado,
        'saldoPendiente': saldo,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'remito',
      id: id,
      upload: () => FirestoreSyncService.instance.subirRemito(id),
    );
    DataRefreshHub.instance.notifyTodo();
  }

  /// Registra un cobro parcial o total sobre un remito.
  Future<void> registrarPago({
    required int remitoId,
    required double monto,
    String medioPago = 'efectivo',
    String observaciones = '',
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a 0');
    }
    final db = await dbHelper.database;
    final rows = await db.query(
      'remitos',
      where: 'id = ?',
      whereArgs: [remitoId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Remito no encontrado');
    }
    final remito = rows.first;
    if (remito['estado'] == 'anulado') {
      throw StateError('No se puede cobrar un remito anulado');
    }
    final total = (remito['total'] as num?)?.toDouble() ?? 0;
    final pagadoActual = (remito['totalPagado'] as num?)?.toDouble() ?? 0;
    var saldo = (remito['saldoPendiente'] as num?)?.toDouble();
    saldo ??= (total - pagadoActual).clamp(0, total).toDouble();
    if (saldo <= 0.009) {
      throw StateError('El remito ya está cobrado');
    }

    final aplicado = monto > saldo ? saldo : monto;
    final nuevoPagado = pagadoActual + aplicado;
    final nuevoSaldo = (total - nuevoPagado).clamp(0, total).toDouble();
    final estadoPago = nuevoSaldo <= 0.009
        ? 'cobrado'
        : nuevoPagado > 0.009
            ? 'parcial'
            : 'pendiente';
    final clienteId = (remito['clienteId'] as num?)?.toInt();
    final numero = remito['numero']?.toString() ?? '$remitoId';

    await db.transaction((txn) async {
      await txn.update(
        'remitos',
        {
          'totalPagado': nuevoPagado,
          'saldoPendiente': nuevoSaldo,
          'estadoPago': estadoPago,
        },
        where: 'id = ?',
        whereArgs: [remitoId],
      );
      // Historial de pago (ventaId=0 = cobro de remito).
      await txn.insert('pagos', {
        'ventaId': 0,
        'clienteId': clienteId,
        'fecha': DateTime.now().toIso8601String(),
        'monto': aplicado,
        'medioPago': medioPago,
        'observaciones': 'Remito $numero'
            '${observaciones.trim().isEmpty ? '' : ' · ${observaciones.trim()}'}',
      });
    });

    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'remito',
      id: remitoId,
      upload: () => FirestoreSyncService.instance.subirRemito(remitoId),
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> anular(int id) async {
    final db = await dbHelper.database;

    await db.transaction((txn) async {
      final remitos = await txn.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (remitos.isEmpty) {
        return;
      }

      final remito = remitos.first;
      if (remito['estado'] == 'anulado') {
        return;
      }

      final items = await txn.query(
        'remito_items',
        where: 'remitoId = ?',
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
        final stockNuevo = stockAnterior + cantidad;

        await txn.rawUpdate(
          'UPDATE productos SET stock = stock + ? WHERE id = ?',
          [cantidad, productoId],
        );

        final movimiento = MovimientoStock(
          productoId: productoId,
          tipo: 'reversion',
          cantidad: cantidad,
          fecha: DateTime.now(),
          remitoId: id.toString(),
          motivo: 'Reversión de remito ${remito['numero']}',
          usuario: AuthService.instance.currentUser?.usuario ?? 'sistema',
          stockAnterior: stockAnterior,
          stockNuevo: stockNuevo,
        );

        await txn.insert('movimientos_stock', movimiento.toMap()..remove('id'));
      }

      await txn.update(
        'remitos',
        {'estado': 'anulado'},
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'remito',
      id: id,
      upload: () => FirestoreSyncService.instance.subirRemito(id),
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<int> cantidad() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery('SELECT COUNT(*) total FROM remitos');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> totalVentas() async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM remitos WHERE estado != 'anulado'",
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> totalVentasPorPeriodo(DateTime desde, DateTime hasta) async {
    final db = await dbHelper.database;
    final r = await db.rawQuery(
      "SELECT SUM(total) total FROM remitos WHERE estado != 'anulado' AND fecha >= ? AND fecha <= ?",
      [desde.toIso8601String(), hasta.toIso8601String()],
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> ventasPorMes({int meses = 6}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT strftime('%Y-%m', fecha) AS mes, SUM(total) AS total
      FROM remitos
      WHERE estado != 'anulado'
      AND fecha >= date('now', '-$meses months')
      GROUP BY strftime('%Y-%m', fecha)
      ORDER BY mes ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> topProductos({int limite = 5}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT p.descripcion, SUM(ri.cantidad) AS totalVendido, SUM(ri.subtotal) AS totalMonto
      FROM remito_items ri
      JOIN productos p ON p.id = ri.productoId
      JOIN remitos r ON r.id = ri.remitoId
      WHERE r.estado != 'anulado'
      GROUP BY ri.productoId
      ORDER BY totalVendido DESC
      LIMIT ?
    ''', [limite]);
  }

  Future<List<Map<String, dynamic>>> topClientes({int limite = 5}) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT c.nombre, COUNT(r.id) AS cantidadRemitos, SUM(r.total) AS totalCompras
      FROM remitos r
      JOIN clientes c ON c.id = r.clienteId
      WHERE r.estado != 'anulado'
      GROUP BY r.clienteId
      ORDER BY totalCompras DESC
      LIMIT ?
    ''', [limite]);
  }
}
