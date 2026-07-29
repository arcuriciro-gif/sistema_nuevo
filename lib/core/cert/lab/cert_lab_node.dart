import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../../../database/database_helper.dart';
import '../../domain/domain_event.dart';
import '../../domain/inventory_ledger_service.dart';
import '../../sync/cloud_sync_throttle.dart';
import '../../sync/sync_outbox.dart';
import 'cert_lab_cloud.dart';
import 'cert_lab_models.dart';

/// Nodo Windows o Android del laboratorio (SQLite propio).
///
/// DatabaseHelper es singleton: el lab abre/cierra al cambiar de nodo.
class CertLabNode {
  CertLabNode({
    required this.id,
    required this.label,
    required this.dir,
  });

  final CertLabNodeId id;
  final String label;
  final Directory dir;

  bool online = true;
  final List<Map<String, dynamic>> pendingStockOps = [];
  final List<Map<String, dynamic>> pendingDocs = [];
  final Set<String> appliedRemoteOpIds = {};

  String get dbPath => p.join(dir.path, '${id.name}.db');

  Future<void> open() async {
    CloudSyncThrottle.resetForTests();
    await DatabaseHelper.instance.cerrar();
    await DatabaseHelper.instance.resetForTests(absolutePath: dbPath);
  }

  Future<dynamic> get database async => DatabaseHelper.instance.database;

  /// Semilla catálogo (stock inicial sin stock_ops).
  Future<void> seedProductos(Map<String, ({int stock, double precio})> items) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final e in items.entries) {
      await db.insert('productos', {
        'codigo': e.key,
        'descripcion': e.key,
        'stock': e.value.stock,
        'precio': e.value.precio,
        'costo': 0,
        'actualizadoEn': now,
      });
    }
  }

  Future<int?> productoId(String codigo) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  Future<int> stockOf(String codigo) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['stock'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['stock'] as num).toInt();
  }

  Future<double> precioOf(String codigo) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['precio'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['precio'] as num).toDouble();
  }

  /// Ajuste/venta local → ledger + cola de lab hacia la nube.
  Future<String> applyLocalStockDelta({
    required String codigo,
    required int delta,
    required String opId,
    String documentType = 'ajuste',
    String? documentId,
  }) async {
    final id = await productoId(codigo);
    if (id == null) {
      throw StateError('[$label] producto $codigo inexistente');
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await InventoryLedgerService.instance.applyInTxn(
        txn,
        DomainEvent(
          eventId: opId,
          type: delta < 0
              ? DomainEventType.mercaderiaEntregada
              : DomainEventType.ajusteInventario,
          aggregateType: documentType,
          aggregateId: documentId ?? opId,
          createdBy: label,
          payload: {
            'documentType': documentType,
            'documentId': documentId ?? opId,
            'lines': [
              InventoryLine(productoId: id, cantidad: delta.abs()).toJson(),
            ],
            if (delta > 0) 'delta': delta,
          },
        ),
        sign: delta < 0 ? -1 : 1,
        movimientoTipo: delta < 0 ? 'salida' : 'entrada',
        // El lab publica a la nube vía CertLabBridge, no vía Firebase real.
        enqueueOutboundStockOps: false,
        enforceStockPolicy: false,
      );
    });
    pendingStockOps.add({
      'opId': opId,
      'codigo': codigo,
      'delta': delta,
      'documentType': documentType,
      'documentId': documentId ?? opId,
      'origin': this.id.name,
    });
    return opId;
  }

  Future<void> setPrecio(String codigo, double precio) async {
    final db = await DatabaseHelper.instance.database;
    final n = await db.update(
      'productos',
      {
        'precio': precio,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'codigo = ?',
      whereArgs: [codigo],
    );
    if (n == 0) throw StateError('[$label] setPrecio: $codigo no existe');
    pendingDocs.add({
      'collection': 'productos',
      'id': codigo,
      'data': {
        'codigo': codigo,
        'precio': precio,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      },
    });
  }

  Future<String> upsertCliente({
    required String syncId,
    required String nombre,
    double saldo = 0,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'clientes',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombre],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('clientes', {
        'nombre': nombre,
        'saldo': saldo,
        'actualizadoEn': now,
      });
    } else {
      await db.update(
        'clientes',
        {'saldo': saldo, 'actualizadoEn': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    pendingDocs.add({
      'collection': 'clientes',
      'id': syncId,
      'data': {
        'syncId': syncId,
        'nombre': nombre,
        'saldo': saldo,
        'actualizadoEn': now,
      },
    });
    return syncId;
  }

  Future<String> upsertProveedor({
    required String syncId,
    required String nombre,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'proveedores',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombre],
      limit: 1,
    );
    if (existing.isEmpty) {
      // Schema main: proveedores sin actualizadoEn en onCreate legacy.
      await db.insert('proveedores', {
        'nombre': nombre,
      });
    }
    pendingDocs.add({
      'collection': 'proveedores',
      'id': syncId,
      'data': {
        'syncId': syncId,
        'nombre': nombre,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      },
    });
    return syncId;
  }

  Future<void> applyRemoteStockOp({
    required String opId,
    required String codigo,
    required int delta,
    String? documentType,
    String? documentId,
  }) async {
    if (appliedRemoteOpIds.contains(opId)) return;
    final id = await productoId(codigo);
    if (id == null) {
      throw StateError('[$label] remote op $opId: falta producto $codigo');
    }
    await InventoryLedgerService.instance.applyRemoteStockOp(
      opId: opId,
      productoId: id,
      codigo: codigo,
      delta: delta,
      documentType: documentType,
      documentId: documentId,
      notify: false,
    );
    appliedRemoteOpIds.add(opId);
  }

  Future<void> applyRemoteProductoDoc(Map<String, dynamic> data) async {
    final codigo = data['codigo']?.toString() ?? '';
    if (codigo.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'productos',
      columns: ['id', 'stock'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    // R6/R7: no pisar stock local con absoluto remoto.
    if (existing.isEmpty) {
      await db.insert('productos', {
        'codigo': codigo,
        'descripcion': data['descripcion'] ?? codigo,
        'stock': 0,
        'precio': data['precio'] ?? 0,
        'costo': data['costo'] ?? 0,
        'actualizadoEn': now,
      });
    } else {
      await db.update(
        'productos',
        {
          if (data['precio'] != null) 'precio': data['precio'],
          if (data['descripcion'] != null) 'descripcion': data['descripcion'],
          'actualizadoEn': now,
        },
        where: 'codigo = ?',
        whereArgs: [codigo],
      );
    }
  }

  Future<void> applyRemoteClienteDoc(Map<String, dynamic> data) async {
    final nombre = data['nombre']?.toString() ?? '';
    if (nombre.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'clientes',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombre],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('clientes', {
        'nombre': nombre,
        'saldo': data['saldo'] ?? 0,
        'actualizadoEn': now,
      });
    } else {
      await db.update(
        'clientes',
        {
          'saldo': data['saldo'] ?? 0,
          'actualizadoEn': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> applyRemoteProveedorDoc(Map<String, dynamic> data) async {
    final nombre = data['nombre']?.toString() ?? '';
    if (nombre.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'proveedores',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombre],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('proveedores', {
        'nombre': nombre,
      });
    }
  }

  Future<int> count(String table) async {
    final db = await DatabaseHelper.instance.database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ??
        0;
  }

  Future<CertLabSnapshot> snapshot() async {
    final db = await DatabaseHelper.instance.database;
    final productos = await db.query(
      'productos',
      columns: ['codigo', 'stock', 'precio'],
      where: "codigo NOT LIKE '__pad_%' AND (deleted_at IS NULL OR deleted_at = '')",
    );
    final stock = <String, int>{};
    final precio = <String, double>{};
    final prodIds = <String>{};
    for (final r in productos) {
      final c = r['codigo']!.toString();
      stock[c] = (r['stock'] as num).toInt();
      precio[c] = (r['precio'] as num).toDouble();
      prodIds.add(c);
    }
    final clientes = await db.query('clientes', columns: ['id', 'nombre', 'saldo']);
    final saldos = <String, double>{};
    final cliIds = <String>{};
    for (final r in clientes) {
      final key = r['nombre']!.toString();
      saldos[key] = (r['saldo'] as num?)?.toDouble() ?? 0;
      cliIds.add(key);
    }
    final prov = await db.query('proveedores', columns: ['nombre']);
    final provIds = prov.map((r) => r['nombre']!.toString()).toSet();

    final pending = await SyncOutbox.instance.countByStatus(
      SyncOutboxStatus.pending,
    );
    final inflight = await SyncOutbox.instance.countByStatus(
      SyncOutboxStatus.inflight,
    );

    return CertLabSnapshot(
      node: id,
      at: DateTime.now().toUtc(),
      counts: {
        'productos': prodIds.length,
        'clientes': cliIds.length,
        'proveedores': provIds.length,
        'ventas': await count('ventas'),
        'compras': await count('compras'),
        'remitos': await count('remitos'),
        'outbox_pending': pending,
        'outbox_inflight': inflight,
      },
      stockByCodigo: stock,
      precioByCodigo: precio,
      saldoByCliente: saldos,
      docIds: {
        'productos': prodIds,
        'clientes': cliIds,
        'proveedores': provIds,
      },
      stockOpIds: {...appliedRemoteOpIds, ...pendingStockOps.map((e) => e['opId'].toString())},
      extra: {
        'online': online,
        'label': label,
        'labPendingStockOps': pendingStockOps.length,
      },
    );
  }

  Future<void> close() async {
    await DatabaseHelper.instance.cerrar();
    CloudSyncThrottle.resetForTests();
  }
}

/// Empuja pendientes del nodo a la nube y baja lo remoto (protocolo lab).
class CertLabBridge {
  CertLabBridge(this.cloud);

  final CertLabCloud cloud;

  Future<void> flush(CertLabNode node) async {
    if (!node.online) return;
    for (final op in List<Map<String, dynamic>>.from(node.pendingStockOps)) {
      final opId = op['opId']?.toString() ?? '';
      if (opId.isEmpty) continue;
      if (!cloud.hasStockOp(opId)) {
        cloud.putStockOp(
          opId: opId,
          codigo: op['codigo']?.toString() ?? '',
          delta: (op['delta'] as num?)?.toInt() ?? 0,
          documentType: op['documentType']?.toString(),
          documentId: op['documentId']?.toString(),
          origin: op['origin']?.toString(),
        );
      }
      node.pendingStockOps.remove(op);
    }
    for (final doc in List<Map<String, dynamic>>.from(node.pendingDocs)) {
      cloud.upsert(
        doc['collection']?.toString() ?? '',
        doc['id']?.toString() ?? '',
        Map<String, dynamic>.from(doc['data'] as Map),
      );
      node.pendingDocs.remove(doc);
    }
  }

  Future<void> pull(CertLabNode node) async {
    if (!node.online) return;
    for (final e in cloud.stockOps.entries) {
      final op = e.value;
      if (op['status']?.toString() != 'applied') continue;
      final opId = e.key;
      if (op['origin']?.toString() == node.id.name) {
        node.appliedRemoteOpIds.add(opId);
        continue;
      }
      await node.applyRemoteStockOp(
        opId: opId,
        codigo: op['codigo']?.toString() ?? '',
        delta: (op['delta'] as num?)?.toInt() ?? 0,
        documentType: op['documentType']?.toString(),
        documentId: op['documentId']?.toString(),
      );
    }
    for (final e in cloud.col('productos').entries) {
      await node.applyRemoteProductoDoc(e.value);
    }
    for (final e in cloud.col('clientes').entries) {
      await node.applyRemoteClienteDoc(e.value);
    }
    for (final e in cloud.col('proveedores').entries) {
      await node.applyRemoteProveedorDoc(e.value);
    }
  }

  /// Sync full-mesh: A→cloud→B y B→cloud→A.
  Future<void> converge(CertLabNode a, CertLabNode b) async {
    await flush(a);
    await flush(b);
    await pull(a);
    await pull(b);
    await flush(a);
    await flush(b);
  }
}
