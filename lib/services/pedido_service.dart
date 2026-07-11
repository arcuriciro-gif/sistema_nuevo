import 'package:sqflite/sqflite.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../database/database_helper.dart';
import '../models/pedido.dart';
import '../models/pedido_item.dart';
import '../models/proveedor.dart';
import 'proveedor_service.dart';
import 'dart:convert';

/// Planilla de pedidos a proveedores (sin impacto en stock).
class PedidoService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProveedorService _proveedorService = ProveedorService();

  /// Proveedores iniciales pedidos en el requerimiento.
  static const proveedoresPlanilla = [
    'Varios',
    'JK',
    'Cuero Sur',
    'Profeta',
    'Parkegon',
  ];

  Future<void> asegurarProveedoresPlanilla() async {
    final existentes = await _proveedorService.obtenerTodos();
    final nombres = existentes.map((p) => p.nombre.trim().toLowerCase()).toSet();
    for (final nombre in proveedoresPlanilla) {
      if (nombres.contains(nombre.toLowerCase())) continue;
      await _proveedorService.insertar(
        Proveedor(
          nombre: nombre,
          telefono: '',
          email: '',
          observaciones: 'Proveedor de planilla de pedidos',
        ),
      );
    }
  }

  Future<String> generarNumero() async {
    final db = await _dbHelper.database;
    final r = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero,3) AS INTEGER)) AS maxN FROM pedidos WHERE numero LIKE 'P-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    return 'P-${(maxN + 1).toString().padLeft(5, '0')}';
  }

  Future<List<Pedido>> obtenerTodos() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pedidos',
      orderBy: 'fecha DESC, id DESC',
    );
    return rows.map(Pedido.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> obtenerTodosConConteo() async {
    final db = await _dbHelper.database;
    return db.rawQuery('''
      SELECT p.*,
        COALESCE((
          SELECT COUNT(*) FROM pedido_items i WHERE i.pedidoId = p.id
        ), 0) AS itemsCount,
        COALESCE((
          SELECT SUM(i.cantidad) FROM pedido_items i WHERE i.pedidoId = p.id
        ), 0) AS cantidadTotal
      FROM pedidos p
      ORDER BY p.proveedorNombre COLLATE NOCASE ASC, p.fecha DESC, p.id DESC
    ''');
  }

  Future<Pedido?> obtenerPorId(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pedidos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Pedido.fromMap(rows.first);
  }

  Future<List<PedidoItem>> obtenerItems(int pedidoId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pedido_items',
      where: 'pedidoId = ?',
      whereArgs: [pedidoId],
      orderBy: 'orden ASC, id ASC',
    );
    return rows.map(PedidoItem.fromMap).toList();
  }

  /// Pedido borrador del día para un proveedor (si existe).
  Future<Pedido?> borradorDelDia(int proveedorId) async {
    final db = await _dbHelper.database;
    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month, ahora.day);
    final fin = inicio.add(const Duration(days: 1));
    final rows = await db.query(
      'pedidos',
      where:
          'proveedorId = ? AND estado = ? AND fecha >= ? AND fecha < ?',
      whereArgs: [
        proveedorId,
        'borrador',
        inicio.toIso8601String(),
        fin.toIso8601String(),
      ],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Pedido.fromMap(rows.first);
  }

  Future<int> guardar(Pedido pedido, List<PedidoItem> items) async {
    final db = await _dbHelper.database;
    final ahora = DateTime.now();
    final pedidoId = await db.transaction((txn) async {
      late int id;
      final map = pedido.toMap()..remove('id');
      map['fechaActualizacion'] = ahora.toIso8601String();
      if (pedido.id == null) {
        map['fechaCreacion'] = ahora.toIso8601String();
        if ((map['numero'] as String?)?.isEmpty ?? true) {
          map['numero'] = await _generarNumeroTxn(txn);
        }
        id = await txn.insert('pedidos', map);
      } else {
        id = pedido.id!;
        await txn.update(
          'pedidos',
          map,
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'pedido_items',
          where: 'pedidoId = ?',
          whereArgs: [id],
        );
      }

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (item.articulo.trim().isEmpty) continue;
        await txn.insert('pedido_items', {
          'pedidoId': id,
          'productoId': item.productoId,
          'articulo': item.articulo.trim(),
          'cantidad': item.cantidad <= 0 ? 1 : item.cantidad,
          'color': item.color.trim(),
          'observaciones': item.observaciones.trim(),
          'orden': i,
        });
      }
      return id;
    });

    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'pedido',
      id: pedidoId,
      upload: () => FirestoreSyncService.instance.subirPedido(pedidoId),
    );
    DataRefreshHub.instance.notifyTodo();
    return pedidoId;
  }

  Future<String> _generarNumeroTxn(Transaction txn) async {
    final r = await txn.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero,3) AS INTEGER)) AS maxN FROM pedidos WHERE numero LIKE 'P-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    return 'P-${(maxN + 1).toString().padLeft(5, '0')}';
  }

  Future<void> cambiarEstado(int pedidoId, String estado) async {
    final db = await _dbHelper.database;
    await db.update(
      'pedidos',
      {
        'estado': estado,
        'fechaActualizacion': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'pedido',
      id: pedidoId,
      upload: () => FirestoreSyncService.instance.subirPedido(pedidoId),
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> eliminar(int pedidoId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'pedidos',
      columns: ['numero'],
      where: 'id = ?',
      whereArgs: [pedidoId],
      limit: 1,
    );
    final numero = rows.isEmpty ? null : rows.first['numero']?.toString();

    await db.transaction((txn) async {
      await txn.delete(
        'pedido_items',
        where: 'pedidoId = ?',
        whereArgs: [pedidoId],
      );
      await txn.delete(
        'pedidos',
        where: 'id = ?',
        whereArgs: [pedidoId],
      );
    });

    if (numero != null && numero.isNotEmpty) {
      await SyncQueueService.instance.pushOrEnqueue(
        entityType: 'pedido',
        entityId: '$pedidoId',
        operation: 'delete',
        payloadJson: jsonEncode({'numero': numero}),
        upload: () =>
            FirestoreSyncService.instance.eliminarPedidoRemoto(numero),
      );
    }
    DataRefreshHub.instance.notifyTodo();
  }
}
