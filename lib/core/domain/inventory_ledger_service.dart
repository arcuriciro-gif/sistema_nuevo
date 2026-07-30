import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../../models/movimiento_stock.dart';
import '../../services/auth_service.dart';
import '../events/data_refresh_hub.dart';
import '../integrity/integrity_policy.dart';
import '../config/platform_capabilities.dart';
import '../sync/cloud_sync_throttle.dart';
import '../sync/firestore_sync_service.dart';
import '../sync/sync_background.dart';
import '../sync/sync_outbox.dart';
import '../sync/stock_ops_applied_store.dart';
import 'domain_event.dart';
import 'event_bus.dart';

/// Ledger de inventario append-only + proyección a `productos.stock`.
class InventoryLedgerService {
  InventoryLedgerService._();
  static final InventoryLedgerService instance = InventoryLedgerService._();

  bool _registered = false;

  void registerHandlers() {
    if (_registered) return;
    _registered = true;
    final bus = DomainEventBus.instance;
    bus.subscribe(DomainEventType.mercaderiaEntregada, _onEntrega);
    bus.subscribe(DomainEventType.mercaderiaEntregaRevertida, _onEntregaRevertida);
    bus.subscribe(DomainEventType.mercaderiaRecibida, _onRecepcion);
    bus.subscribe(DomainEventType.mercaderiaRecepcionRevertida, _onRecepcionRevertida);
    bus.subscribe(DomainEventType.ajusteInventario, _onAjuste);
  }

  void resetForTests() {
    _registered = false;
  }

  Future<void> _onEntrega(DomainEvent e) =>
      _applyInventory(e, sign: -1, movimientoTipo: 'salida');

  Future<void> _onEntregaRevertida(DomainEvent e) =>
      _applyInventory(e, sign: 1, movimientoTipo: 'entrada');

  Future<void> _onRecepcion(DomainEvent e) =>
      _applyInventory(e, sign: 1, movimientoTipo: 'entrada');

  Future<void> _onRecepcionRevertida(DomainEvent e) =>
      _applyInventory(e, sign: -1, movimientoTipo: 'salida');

  Future<void> _onAjuste(DomainEvent e) async {
    final tipo = e.payload['tipo']?.toString() ?? 'entrada';
    final sign = tipo == 'salida' ? -1 : 1;
    await _applyInventory(e, sign: sign, movimientoTipo: tipo);
  }

  List<InventoryLine> _linesFrom(DomainEvent event) {
    final rawLines = (event.payload['lines'] as List?) ?? const [];
    return rawLines
        .whereType<Map>()
        .map((m) => InventoryLine.fromJson(Map<String, dynamic>.from(m)))
        .where((l) => l.cantidad != 0)
        .toList();
  }

  /// Aplica entrega/recepción dentro de una TX comercial ya abierta (C2).
  /// Retorna `true` si escribió ledger; `false` si era idempotente.
  Future<bool> applyInTxn(
    DatabaseExecutor txn,
    DomainEvent event, {
    required int sign,
    required String movimientoTipo,
    bool enforceStockPolicy = true,
    /// Encola stock_ops al outbox en la MISMA TX (origen local).
    /// Remoto (peer apply) debe pasar false.
    bool enqueueOutboundStockOps = true,
  }) async {
    final existing = await txn.query(
      'domain_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: [event.eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      debugPrint('InventoryLedger: skip idempotent ${event.eventId}');
      return false;
    }

    final rawLines = _linesFrom(event);
    if (rawLines.isEmpty) return false;

    // Agregar líneas duplicadas del mismo producto (evita choque UNIQUE event_id).
    final aggregated = <int, int>{};
    for (final line in rawLines) {
      if (line.cantidad < 0) {
        throw ArgumentError(
          'Cantidad negativa inválida en ledger (producto ${line.productoId}).',
        );
      }
      aggregated.update(
        line.productoId,
        (prev) => prev + line.cantidad.abs(),
        ifAbsent: () => line.cantidad.abs(),
      );
    }
    final lines = aggregated.entries
        .map((e) => InventoryLine(productoId: e.key, cantidad: e.value))
        .toList();

    // Validación de política dentro de la misma TX (stock actual).
    // Remoto (stock_ops peer): no bloquear — el origen ya comprometió el delta.
    if (enforceStockPolicy) {
      for (final line in lines) {
        final prod = await txn.query(
          'productos',
          columns: ['stock', 'codigo'],
          where: 'id = ?',
          whereArgs: [line.productoId],
          limit: 1,
        );
        if (prod.isEmpty) {
          throw StateError(
            'Producto ${line.productoId} inexistente: no se puede mover stock.',
          );
        }
        final stockBefore = (prod.first['stock'] as num?)?.toInt() ?? 0;
        final stockAfter = stockBefore + sign * line.cantidad.abs();
        if (!await IntegrityPolicy.instance.permiteStockResultante(stockAfter)) {
          final codigo =
              prod.first['codigo']?.toString() ?? '${line.productoId}';
          throw StateError(
            'Stock insuficiente para $codigo '
            '(hay $stockBefore, se necesitan ${line.cantidad.abs()}). '
            'Activá "Permitir stock negativo" en Configuración si corresponde.',
          );
        }
      }
    } else {
      for (final line in lines) {
        final prod = await txn.query(
          'productos',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [line.productoId],
          limit: 1,
        );
        if (prod.isEmpty) {
          throw StateError(
            'Producto ${line.productoId} inexistente: no se puede mover stock.',
          );
        }
      }
    }

    final docType = event.payload['documentType']?.toString();
    final docId = event.payload['documentId']?.toString();
    final motivo = event.payload['motivo']?.toString() ?? event.type;
    final usuario = event.createdBy ??
        AuthService.instance.currentUser?.usuario ??
        'sistema';

    await txn.insert('domain_events', event.toRow());
    for (final line in lines) {
      final prod = await txn.query(
        'productos',
        columns: ['stock', 'codigo'],
        where: 'id = ?',
        whereArgs: [line.productoId],
        limit: 1,
      );
      if (prod.isEmpty) {
        throw StateError(
          'Producto ${line.productoId} inexistente durante applyInTxn.',
        );
      }
      final stockBefore = (prod.first['stock'] as num?)?.toInt() ?? 0;
      final codigo = line.productoCodigo ?? prod.first['codigo']?.toString();
      final delta = sign * line.cantidad.abs();
      final stockAfter = stockBefore + delta;

      // NO tocar actualizadoEn: es LWW de catálogo (precio/delete).
      // Campo: stock_ops bumpaban actualizadoEn → upload producto pisaba
      // deleted_at remoto → 2884 vs 2883 entre dispositivos.
      final updated = await txn.rawUpdate(
        'UPDATE productos SET stock = stock + ? WHERE id = ?',
        [delta, line.productoId],
      );
      if (updated != 1) {
        throw StateError(
          'No se pudo proyectar stock del producto ${line.productoId}.',
        );
      }

      final lineEventId = '${event.eventId}:${line.productoId}';
      await txn.insert('inventory_ledger', {
        'event_id': lineEventId,
        'parent_event_id': event.eventId,
        'product_id': line.productoId,
        'product_codigo': codigo,
        'delta': delta,
        'reason': motivo,
        'document_type': docType,
        'document_id': docId,
        'stock_before': stockBefore,
        'stock_after': stockAfter,
        'created_at': event.createdAt.toIso8601String(),
      });

      await txn.insert('movimientos_stock', {
        ...MovimientoStock(
          productoId: line.productoId,
          tipo: movimientoTipo,
          cantidad: line.cantidad.abs(),
          fecha: event.createdAt.toLocal(),
          remitoId: docType == 'remito' ? docId : null,
          motivo: motivo,
          usuario: usuario,
          stockAnterior: stockBefore,
          stockNuevo: stockAfter,
        ).toMap()
          ..remove('id'),
      });

      // Outbox + dedupe durable en la MISMA TX que el ledger (no post-commit).
      if (enqueueOutboundStockOps) {
        final cloudOpId = '${event.eventId}_${line.productoId}';
        final codCloud = (codigo ?? '').trim();
        // G2: sin código no hay clave cloud → rechazar TX (no perder op en silencio).
        if (codCloud.isEmpty) {
          throw StateError(
            'Producto ${line.productoId} sin codigo: '
            'no se puede encolar stock_op (garantía G2).',
          );
        }
        await SyncOutbox.instance.enqueueStockOpInTxn(
          txn,
          opId: cloudOpId,
          codigo: codCloud,
          delta: delta,
          documentType: docType,
          documentId: docId,
        );
        await StockOpsAppliedStore.instance.markInTxn(
          txn,
          opId: cloudOpId,
          origin: 'local',
          codigo: codCloud,
          delta: delta,
        );
      }
    }
    return true;
  }

  /// Aplica un stock_op remoto al ledger local (sin re-subir a la nube).
  /// Idempotente por [opId] (= event_id).
  Future<bool> applyRemoteStockOp({
    required String opId,
    required int productoId,
    required String codigo,
    required int delta,
    String? documentType,
    String? documentId,
    bool notify = true,
  }) async {
    if (delta == 0 || opId.isEmpty) return false;
    final db = await DatabaseHelper.instance.database;
    final applied = await db.transaction((txn) async {
      return _applyRemoteStockOpInTxn(
        txn,
        opId: opId,
        productoId: productoId,
        codigo: codigo,
        delta: delta,
        documentType: documentType,
        documentId: documentId,
      );
    });
    if (applied && notify) {
      DataRefreshHub.instance.notifyStock();
      DataRefreshHub.instance.notifyProductos();
    }
    return applied;
  }

  /// Aplica varios stock_ops en TX(s).
  ///
  /// Windows: micro-lotes + yield entre TX (un batch grande + notify
  /// concurrente seguía tumbando el .exe en "Actualizar ahora").
  Future<int> applyRemoteStockOpsBatch(
    List<
        ({
          String opId,
          int productoId,
          String codigo,
          int delta,
          String? documentType,
          String? documentId,
        })> ops, {
    int? microBatchSize,
    int yieldMs = 0,
  }) async {
    if (ops.isEmpty) return 0;
    final db = await DatabaseHelper.instance.database;
    var applied = 0;
    final chunk = (microBatchSize != null && microBatchSize > 0)
        ? microBatchSize
        : ops.length;
    for (var i = 0; i < ops.length; i += chunk) {
      final slice = ops.sublist(
        i,
        i + chunk > ops.length ? ops.length : i + chunk,
      );
      await db.transaction((txn) async {
        for (final op in slice) {
          final ok = await _applyRemoteStockOpInTxn(
            txn,
            opId: op.opId,
            productoId: op.productoId,
            codigo: op.codigo,
            delta: op.delta,
            documentType: op.documentType,
            documentId: op.documentId,
          );
          if (ok) applied++;
        }
      });
      if (yieldMs > 0 && i + chunk < ops.length) {
        await Future<void>.delayed(Duration(milliseconds: yieldMs));
      }
    }
    if (applied > 0) {
      DataRefreshHub.instance.notifyStock();
      DataRefreshHub.instance.notifyProductos();
    }
    return applied;
  }

  /// Alinea `productos.stock` con ledger local (base + Σ delta).
  ///
  /// No escribe la nube: solo repara proyección local divergente
  /// (campo: stock “fantasma” tras crash mid-apply).
  Future<int> repararProyeccionesDivergentes({int limit = 80}) async {
    final db = await DatabaseHelper.instance.database;
    final productIds = await db.rawQuery(
      '''
      SELECT DISTINCT product_id AS id
      FROM inventory_ledger
      ORDER BY product_id ASC
      LIMIT ?
      ''',
      [limit],
    );
    var repaired = 0;
    for (final row in productIds) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final first = await db.query(
        'inventory_ledger',
        columns: ['stock_before'],
        where: 'product_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (first.isEmpty) continue;
      final base = (first.first['stock_before'] as num?)?.toInt() ?? 0;
      final sumRows = await db.rawQuery(
        'SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger WHERE product_id = ?',
        [id],
      );
      final sumDelta = (sumRows.first['s'] as num?)?.toInt() ?? 0;
      final expected = base + sumDelta;
      final prod = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (prod.isEmpty) continue;
      final actual = (prod.first['stock'] as num?)?.toInt() ?? 0;
      if (actual == expected) continue;
      await db.update(
        'productos',
        {'stock': expected},
        where: 'id = ?',
        whereArgs: [id],
      );
      repaired++;
    }
    if (repaired > 0) {
      DataRefreshHub.instance.notifyStock();
      DataRefreshHub.instance.notifyProductos();
    }
    return repaired;
  }

  Future<bool> _applyRemoteStockOpInTxn(
    DatabaseExecutor txn, {
    required String opId,
    required int productoId,
    required String codigo,
    required int delta,
    String? documentType,
    String? documentId,
  }) async {
    if (delta == 0 || opId.isEmpty) return false;
    final tipo = delta > 0 ? 'entrada' : 'salida';
    // Atribuir al documento comercial cuando viene en la op (anular seguidor).
    final dt = (documentType ?? '').trim();
    final di = (documentId ?? '').trim();
    final docType = dt.isNotEmpty ? dt : 'stock_op';
    final docId = di.isNotEmpty ? di : opId;
    final event = DomainEvent(
      eventId: opId,
      type: DomainEventType.ajusteInventario,
      aggregateType: 'producto',
      aggregateId: '$productoId',
      createdBy: 'sync',
      payload: {
        'tipo': tipo,
        'motivo': 'Sync stock_op $opId',
        'documentType': docType,
        'documentId': docId,
        'lines': [
          InventoryLine(
            productoId: productoId,
            cantidad: delta.abs(),
            productoCodigo: codigo,
          ).toJson(),
        ],
      },
    );
    final ok = await applyInTxn(
      txn,
      event,
      sign: delta > 0 ? 1 : -1,
      movimientoTipo: tipo,
      // Peer debe aplicar el mismo delta aunque deje negativo (origen ya OK).
      enforceStockPolicy: false,
      // No re-subir a la nube: ya viene de stock_ops remoto.
      enqueueOutboundStockOps: false,
    );
    if (ok) {
      await StockOpsAppliedStore.instance.markInTxn(
        txn,
        opId: opId,
        origin: 'remote',
        codigo: codigo,
        delta: delta,
      );
    }
    return ok;
  }

  /// Reverso local de stock de un documento (p. ej. tombstone remoto).
  /// No encola cloud — los deltas remotos llegan por stock_ops.
  Future<bool> reverseDocumentLocally({
    required String documentType,
    required String documentId,
    required String eventId,
    required List<InventoryLine> lines,
    required int sign,
    required String movimientoTipo,
    String motivo = 'Reverso local por sync',
  }) async {
    if (lines.isEmpty) return false;
    final event = DomainEvent(
      eventId: eventId,
      type: sign > 0
          ? DomainEventType.mercaderiaEntregaRevertida
          : DomainEventType.mercaderiaRecepcionRevertida,
      aggregateType: documentType,
      aggregateId: documentId,
      createdBy: 'sync',
      payload: {
        'documentType': documentType,
        'documentId': documentId,
        'motivo': motivo,
        'lines': lines.map((l) => l.toJson()).toList(),
      },
    );
    final db = await DatabaseHelper.instance.database;
    final applied = await db.transaction((txn) async {
      return applyInTxn(
        txn,
        event,
        sign: sign,
        movimientoTipo: movimientoTipo,
        // Tombstone reverse es peer-local: NO re-subir (origen ya emite
        // stock_ops de anulación). Default true duplicaba cloud (G1/G6).
        enqueueOutboundStockOps: false,
      );
    });
    if (applied) {
      DataRefreshHub.instance.notifyStock();
    }
    return applied;
  }

  Future<int> ledgerNetForDocument({
    required String documentType,
    required String documentId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger '
      'WHERE document_type = ? AND document_id = ?',
      [documentType, documentId],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  /// Tras commit local: flush de stock_ops (outbox ya encolado en TX).
  ///
  /// NUNCA subir el documento producto acá: el catálogo no cambió.
  /// Campo: subirProducto tras Δstock reescribía actualizadoEn+deleted_at
  /// y “revivía” SKUs borrados en el otro dispositivo (2884↔2883).
  void enqueueCloudAfterApply(DomainEvent event, {required int sign}) {
    final lines = _linesFrom(event);
    if (lines.isEmpty) return;
    syncInBackground(
      CloudSyncThrottle.enqueue(() async {
        final windows = PlatformCapabilities.isWindowsDesktop;
        for (final line in lines) {
          final delta = sign * line.cantidad.abs();
          final opId = '${event.eventId}_${line.productoId}';
          await FirestoreSyncService.instance.ajustarStockEnNube(
            productoId: line.productoId,
            delta: delta,
            opId: opId,
            flushImmediately: !windows,
            documentType: event.payload['documentType']?.toString(),
            documentId: event.payload['documentId']?.toString(),
            alreadyEnqueuedInTxn: true,
          );
        }
      }, tag: 'InventoryLedger cloud'),
      tag: 'InventoryLedger cloud',
    );
    DataRefreshHub.instance.notifyStock();
    DataRefreshHub.instance.notifyProductos();
  }

  Future<void> _applyInventory(
    DomainEvent event, {
    required int sign,
    required String movimientoTipo,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final applied = await db.transaction((txn) async {
      return applyInTxn(
        txn,
        event,
        sign: sign,
        movimientoTipo: movimientoTipo,
      );
    });
    if (applied) {
      enqueueCloudAfterApply(event, sign: sign);
    }
  }

  /// Reconstruye stock de un producto desde el ledger (certificación).
  Future<int> reconstruirStock(int productoId, {int stockInicial = 0}) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger WHERE product_id = ?',
      [productoId],
    );
    return stockInicial + ((r.first['s'] as num?)?.toInt() ?? 0);
  }

  Future<bool> verificarProyeccion(int productoId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final actual = (rows.first['stock'] as num?)?.toInt() ?? 0;
    final first = await db.query(
      'inventory_ledger',
      columns: ['stock_before'],
      where: 'product_id = ?',
      whereArgs: [productoId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (first.isEmpty) {
      return true;
    }
    final base = (first.first['stock_before'] as num?)?.toInt() ?? 0;
    final reconstruido = await reconstruirStock(productoId, stockInicial: base);
    return actual == reconstruido;
  }

  /// Valida que aplicar [lines] con [sign] no deje stock negativo (si la política lo prohíbe).
  Future<void> assertPuedeAplicar({
    required List<InventoryLine> lines,
    required int sign,
  }) async {
    final db = await DatabaseHelper.instance.database;
    for (final line in lines) {
      if (line.cantidad == 0) continue;
      final prod = await db.query(
        'productos',
        columns: ['stock', 'codigo'],
        where: 'id = ?',
        whereArgs: [line.productoId],
        limit: 1,
      );
      final stockBefore =
          (prod.isNotEmpty ? prod.first['stock'] as num? : 0)?.toInt() ?? 0;
      final delta = sign * line.cantidad.abs();
      final stockAfter = stockBefore + delta;
      if (!await IntegrityPolicy.instance.permiteStockResultante(stockAfter)) {
        final codigo = prod.isNotEmpty
            ? (prod.first['codigo']?.toString() ?? '${line.productoId}')
            : '${line.productoId}';
        throw StateError(
          'Stock insuficiente para $codigo '
          '(hay $stockBefore, se necesitan ${line.cantidad.abs()}). '
          'Activá "Permitir stock negativo" en Configuración si corresponde.',
        );
      }
    }
  }
}
