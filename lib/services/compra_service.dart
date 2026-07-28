import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../core/config/device_identity.dart';
import '../core/config/platform_capabilities.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/domain/inventory_delivery_policy.dart';
import '../core/domain/inventory_ledger_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/cloud_sync_throttle.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/stable_document_id.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/compra.dart';
import '../models/compra_detalle.dart';
import 'auth_service.dart';

class CompraService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<String> generarNumero() async {
    final db = await dbHelper.database;
    final tag = await DeviceIdentity.shortTag();
    final r = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero, 3, 5) AS INTEGER)) AS maxN "
      "FROM compras WHERE numero LIKE 'C-%'",
    );
    final maxN = (r.first['maxN'] as num?)?.toInt() ?? 0;
    return 'C-${(maxN + 1).toString().padLeft(5, '0')}-$tag';
  }

  Future<void> _actualizarCostoEnTxn(
    DatabaseExecutor txn, {
    required int productoId,
    required double costoNuevo,
    required String motivo,
  }) async {
    final productoRows = await txn.query(
      'productos',
      columns: ['costo', 'precio'],
      where: 'id = ?',
      whereArgs: [productoId],
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

    await txn.rawUpdate(
      'UPDATE productos SET costo = ?, actualizadoEn = ? WHERE id = ?',
      [costoNuevo, DateTime.now().toUtc().toIso8601String(), productoId],
    );

    if (costoAnterior != costoNuevo) {
      final variacion = costoAnterior > 0
          ? ((costoNuevo - costoAnterior) / costoAnterior) * 100
          : 0.0;
      await txn.insert('historial_precios', {
        'productoId': productoId,
        'fecha': DateTime.now().toIso8601String(),
        'usuario': AuthService.instance.currentUser?.usuario ?? 'sistema',
        'costoAnterior': costoAnterior,
        'costoNuevo': costoNuevo,
        'precioAnterior': precioAnterior,
        'precioNuevo': precioAnterior,
        'porcentaje': variacion,
        'listaModificada': 'Costo',
        'motivo': motivo,
      });
    }
  }

  Future<int> insertar(Compra compra, List<CompraDetalle> items) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      AuthModules.compras,
      AuthzAction.crear,
      operacion: 'crear compra',
    );
    final db = await dbHelper.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    DomainEvent? invEvent;

    final compraId = await db.transaction((txn) async {
      final id = await txn.insert('compras', {
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

      final lines = <Map<String, dynamic>>[];
      for (final item in items) {
        await txn.insert('compra_items', {
          'compraId': id,
          'productoId': item.productoId,
          'productoDescripcion': item.productoDescripcion,
          'cantidad': item.cantidad,
          'costo': item.costo,
          'subtotal': item.subtotal,
        });
        await _actualizarCostoEnTxn(
          txn,
          productoId: item.productoId,
          costoNuevo: item.costo,
          motivo: 'Compra ${compra.numero}',
        );
        if (item.cantidad != 0) {
          lines.add(InventoryLine(
            productoId: item.productoId,
            cantidad: item.cantidad,
          ).toJson());
        }
      }

      if (lines.isNotEmpty) {
        invEvent = DomainEvent(
          eventId: 'inv:recepcion:compra:$id',
          type: DomainEventType.mercaderiaRecibida,
          aggregateType: 'compra',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'compra',
            'documentId': stableCommercialDocumentId(
              numero: compra.numero,
              localId: id,
              fallbackPrefix: 'C_',
            ),
            'documentNumero': compra.numero,
            'motivo': 'Recepción por compra ${compra.numero}',
            'lines': lines,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          invEvent!,
          sign: 1,
          movimientoTipo: 'entrada',
        );
      }

      return id;
    });

    if (invEvent != null) {
      InventoryLedgerService.instance
          .enqueueCloudAfterApply(invEvent!, sign: 1);
      await DomainEventBus.instance.publish(invEvent!);
    }

    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await FirestoreSyncService.instance.subirCompra(compraId);
        }, tag: 'subirCompra'),
        tag: 'subirCompra',
      );
    } else {
      syncInBackground(
        FirestoreSyncService.instance.subirCompra(compraId),
        tag: 'subirCompra',
      );
    }
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

  Future<int> _ledgerNetCompra(
    DatabaseExecutor txn,
    int compraId, {
    String? numero,
  }) {
    return ledgerNetForDocumentCandidates(
      txn,
      documentType: 'compra',
      numero: numero,
      localId: compraId,
    );
  }

  Future<void> anular(int id, {bool syncAfter = true}) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      'compras',
      AuthzAction.anular,
      operacion: 'anular compra',
    );
    final db = await dbHelper.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;
    DomainEvent? invEvent;

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
      final numero = compra['numero']?.toString();

      final items = await txn.query(
        'compra_items',
        where: 'compraId = ?',
        whereArgs: [id],
      );

      final lines = <Map<String, dynamic>>[];
      for (final item in items) {
        final productoId = (item['productoId'] as num?)?.toInt();
        if (productoId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad == 0) continue;
        lines.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      final net = await _ledgerNetCompra(txn, id, numero: numero);
      final debeRevertir = lines.isNotEmpty && net > 0;

      await txn.update(
        'compras',
        {'estado': 'anulada'},
        where: 'id = ?',
        whereArgs: [id],
      );

      if (debeRevertir) {
        invEvent = DomainEvent(
          eventId: InventoryDeliveryPolicy.eventIdRecepcionRevCompra(
            id,
            rev: rev,
          ),
          type: DomainEventType.mercaderiaRecepcionRevertida,
          aggregateType: 'compra',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'compra',
            'documentId': stableCommercialDocumentId(numero: numero, localId: id, fallbackPrefix: 'C_'),
            'documentNumero': numero,
            'motivo': 'Reverso recepción compra ${numero ?? id}',
            'lines': lines,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          invEvent!,
          sign: -1,
          movimientoTipo: 'salida',
        );
      }
    });

    if (invEvent != null) {
      InventoryLedgerService.instance
          .enqueueCloudAfterApply(invEvent!, sign: -1);
      await DomainEventBus.instance.publish(invEvent!);
    }

    if (syncAfter) {
      syncInBackground(
        FirestoreSyncService.instance.subirCompra(id),
        tag: 'subirCompra',
      );
    }
    DataRefreshHub.instance.notifyTodo();
  }

  /// Reabre una compra anulada: vuelve a confirmar y re-aplica vía ledger.
  Future<void> reabrir(int id, {bool syncAfter = true}) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      AuthModules.compras,
      AuthzAction.anular,
      operacion: 'reabrir compra',
    );
    final db = await dbHelper.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;
    DomainEvent? invEvent;

    await db.transaction((txn) async {
      final compras = await txn.query(
        'compras',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (compras.isEmpty) {
        throw StateError('Compra no encontrada');
      }
      final compra = compras.first;
      if (compra['estado'] != 'anulada') {
        throw StateError('Solo se pueden reabrir compras anuladas');
      }
      final numero = compra['numero']?.toString() ?? '';

      final items = await txn.query(
        'compra_items',
        where: 'compraId = ?',
        whereArgs: [id],
      );
      final lines = <Map<String, dynamic>>[];
      for (final item in items) {
        final productoId = (item['productoId'] as num?)?.toInt();
        if (productoId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad == 0) continue;
        lines.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      await txn.update(
        'compras',
        {'estado': 'confirmada'},
        where: 'id = ?',
        whereArgs: [id],
      );

      if (lines.isNotEmpty) {
        invEvent = DomainEvent(
          eventId: InventoryDeliveryPolicy.eventIdRecepcionReopenCompra(
            id,
            rev: rev,
          ),
          type: DomainEventType.mercaderiaRecibida,
          aggregateType: 'compra',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'compra',
            'documentId': stableCommercialDocumentId(numero: numero, localId: id, fallbackPrefix: 'C_'),
            'documentNumero': numero,
            'motivo': 'Reapertura recepción compra $numero',
            'lines': lines,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          invEvent!,
          sign: 1,
          movimientoTipo: 'entrada',
        );
      }
    });

    if (invEvent != null) {
      InventoryLedgerService.instance.enqueueCloudAfterApply(invEvent!, sign: 1);
      await DomainEventBus.instance.publish(invEvent!);
    }

    if (syncAfter) {
      syncInBackground(
        FirestoreSyncService.instance.subirCompra(id),
        tag: 'subirCompra',
      );
    }
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> actualizar(
    int id,
    Compra compra,
    List<CompraDetalle> items,
  ) async {
    DomainBootstrap.ensureInitialized();
    AuthorizationService.instance.require(
      AuthModules.compras,
      AuthzAction.editar,
      operacion: 'editar compra',
    );
    final db = await dbHelper.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    // Cada edición tiene revision única → no hay skip idempotente falso.
    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;
    DomainEvent? revEvent;
    DomainEvent? newEvent;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'compras',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Compra no encontrada');
      }
      final actual = rows.first;
      if (actual['estado'] == 'anulada') {
        throw StateError('No se puede editar una compra anulada');
      }
      final numero = actual['numero']?.toString() ?? compra.numero;

      final oldItems = await txn.query(
        'compra_items',
        where: 'compraId = ?',
        whereArgs: [id],
      );
      final linesOld = <Map<String, dynamic>>[];
      for (final item in oldItems) {
        final productoId = (item['productoId'] as num?)?.toInt();
        if (productoId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad == 0) continue;
        linesOld.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      await txn.update(
        'compras',
        {
          'proveedorId': compra.proveedorId,
          'proveedorNombre': compra.proveedorNombre,
          'factura': compra.factura,
          'total': compra.total,
          'descuento': compra.descuento,
          'iva': compra.iva,
          'observaciones': compra.observaciones,
          'estado': 'confirmada',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'compra_items',
        where: 'compraId = ?',
        whereArgs: [id],
      );

      final linesNew = <Map<String, dynamic>>[];
      for (final item in items) {
        await txn.insert('compra_items', {
          'compraId': id,
          'productoId': item.productoId,
          'productoDescripcion': item.productoDescripcion,
          'cantidad': item.cantidad,
          'costo': item.costo,
          'subtotal': item.subtotal,
        });
        await _actualizarCostoEnTxn(
          txn,
          productoId: item.productoId,
          costoNuevo: item.costo,
          motivo: 'Edición compra $numero',
        );
        if (item.cantidad != 0) {
          linesNew.add(InventoryLine(
            productoId: item.productoId,
            cantidad: item.cantidad,
          ).toJson());
        }
      }

      if (linesOld.isNotEmpty) {
        revEvent = DomainEvent(
          eventId: 'inv:recepcion_rev:compra:$id:edit:$rev',
          type: DomainEventType.mercaderiaRecepcionRevertida,
          aggregateType: 'compra',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'compra',
            'documentId': stableCommercialDocumentId(numero: numero, localId: id, fallbackPrefix: 'C_'),
            'documentNumero': numero,
            'motivo': 'Reverso por edición compra $numero',
            'lines': linesOld,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          revEvent!,
          sign: -1,
          movimientoTipo: 'salida',
        );
      }

      if (linesNew.isNotEmpty) {
        newEvent = DomainEvent(
          eventId: 'inv:recepcion:compra:$id:edit:$rev',
          type: DomainEventType.mercaderiaRecibida,
          aggregateType: 'compra',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'compra',
            'documentId': stableCommercialDocumentId(numero: numero, localId: id, fallbackPrefix: 'C_'),
            'documentNumero': numero,
            'motivo': 'Recepción por edición compra $numero',
            'lines': linesNew,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          newEvent!,
          sign: 1,
          movimientoTipo: 'entrada',
        );
      }
    });

    if (revEvent != null) {
      InventoryLedgerService.instance
          .enqueueCloudAfterApply(revEvent!, sign: -1);
      await DomainEventBus.instance.publish(revEvent!);
    }
    if (newEvent != null) {
      InventoryLedgerService.instance
          .enqueueCloudAfterApply(newEvent!, sign: 1);
      await DomainEventBus.instance.publish(newEvent!);
    }

    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await FirestoreSyncService.instance.subirCompra(id);
        }, tag: 'subirCompra'),
        tag: 'subirCompra',
      );
    } else {
      syncInBackground(
        FirestoreSyncService.instance.subirCompra(id),
        tag: 'subirCompra',
      );
    }
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> eliminar(int id) async {
    DomainBootstrap.ensureInitialized();
    final auth = AuthorizationService.instance;
    if (!auth.puede(AuthModules.compras, AuthzAction.eliminar) &&
        !auth.puede(AuthModules.compras, AuthzAction.anular)) {
      auth.require(
        AuthModules.compras,
        AuthzAction.eliminar,
        operacion: 'eliminar compra',
      );
    }
    final db = await dbHelper.database;
    final rows = await db.query(
      'compras',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final compra = rows.first;
    final numero = compra['numero']?.toString() ?? '';
    if (compra['estado'] != 'anulada') {
      await anular(id, syncAfter: false);
    }
    if (numero.isNotEmpty) {
      try {
        await FirestoreSyncService.instance
            .eliminarCompraRemota(numero, localId: id);
      } catch (e) {
        assert(() {
          // ignore: avoid_print
          print('eliminarCompraRemota: $e');
          return true;
        }());
      }
    }
    await db.delete('compra_items', where: 'compraId = ?', whereArgs: [id]);
    await db.delete('compras', where: 'id = ?', whereArgs: [id]);
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

  Future<List<Map<String, dynamic>>> obtenerPorPeriodo(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await dbHelper.database;
    final fin = DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59);
    return db.rawQuery(
      '''
      SELECT c.*, p.nombre AS proveedorNombreActual
      FROM compras c
      LEFT JOIN proveedores p ON p.id = c.proveedorId
      WHERE (c.estado IS NULL OR c.estado != 'anulada')
        AND datetime(c.fecha) >= datetime(?)
        AND datetime(c.fecha) <= datetime(?)
      ORDER BY datetime(c.fecha) DESC, datetime(c.fechaCreacion) DESC
      ''',
      [desde.toIso8601String(), fin.toIso8601String()],
    );
  }

  Future<double> totalComprasPorPeriodo(DateTime desde, DateTime hasta) async {
    final db = await dbHelper.database;
    final fin = DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59);
    final r = await db.rawQuery(
      '''
      SELECT SUM(total) total FROM compras
      WHERE (estado IS NULL OR estado != 'anulada')
        AND datetime(fecha) >= datetime(?)
        AND datetime(fecha) <= datetime(?)
      ''',
      [desde.toIso8601String(), fin.toIso8601String()],
    );
    return (r.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> comprasPorMes({int meses = 6}) async {
    final db = await dbHelper.database;
    final safeMeses = meses < 1 ? 1 : meses;
    return db.rawQuery('''
      SELECT strftime('%Y-%m', fecha) AS mes, SUM(total) AS total
      FROM compras
      WHERE (estado IS NULL OR estado != 'anulada')
        AND fecha >= date('now', ?)
      GROUP BY strftime('%Y-%m', fecha)
      ORDER BY mes ASC
    ''', ['-$safeMeses months']);
  }
}
