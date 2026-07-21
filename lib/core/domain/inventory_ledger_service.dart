import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../../models/movimiento_stock.dart';
import '../../services/auth_service.dart';
import '../events/data_refresh_hub.dart';
import '../sync/firestore_sync_service.dart';
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

  @visibleForTesting
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

  Future<void> _applyInventory(
    DomainEvent event, {
    required int sign,
    required String movimientoTipo,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'domain_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: [event.eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      debugPrint('InventoryLedger: skip idempotent ${event.eventId}');
      return;
    }

    final rawLines = (event.payload['lines'] as List?) ?? const [];
    final lines = rawLines
        .whereType<Map>()
        .map((m) => InventoryLine.fromJson(Map<String, dynamic>.from(m)))
        .where((l) => l.cantidad != 0)
        .toList();
    if (lines.isEmpty) return;

    final docType = event.payload['documentType']?.toString();
    final docId = event.payload['documentId']?.toString();
    final motivo = event.payload['motivo']?.toString() ?? event.type;
    final usuario = event.createdBy ??
        AuthService.instance.currentUser?.usuario ??
        'sistema';

    await db.transaction((txn) async {
      await txn.insert('domain_events', event.toRow());
      for (final line in lines) {
        final prod = await txn.query(
          'productos',
          columns: ['stock', 'codigo'],
          where: 'id = ?',
          whereArgs: [line.productoId],
          limit: 1,
        );
        final stockBefore =
            (prod.isNotEmpty ? prod.first['stock'] as num? : 0)?.toInt() ?? 0;
        final codigo = line.productoCodigo ??
            (prod.isNotEmpty ? prod.first['codigo']?.toString() : null);
        final delta = sign * line.cantidad.abs();
        final stockAfter = stockBefore + delta;

        await txn.rawUpdate(
          'UPDATE productos SET stock = stock + ?, actualizadoEn = ? WHERE id = ?',
          [delta, DateTime.now().toUtc().toIso8601String(), line.productoId],
        );

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

        // Compat UI kardex legado.
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
      }
    });

    // Sync nube idempotente por eventId de línea.
    unawaited(() async {
      try {
        for (final line in lines) {
          final delta = sign * line.cantidad.abs();
          await FirestoreSyncService.instance.ajustarStockEnNube(
            productoId: line.productoId,
            delta: delta,
            opId: '${event.eventId}_${line.productoId}',
          );
          await FirestoreSyncService.instance
              .subirProductoPorId(line.productoId);
        }
      } catch (e) {
        debugPrint('InventoryLedger cloud sync: $e');
      }
    }());

    DataRefreshHub.instance.notifyStock();
    DataRefreshHub.instance.notifyProductos();
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
    final reconstruido = await reconstruirStock(productoId);
    return actual == reconstruido;
  }
}
