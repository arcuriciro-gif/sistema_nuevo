import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../database/database_helper.dart';
import '../domain/domain_event.dart';
import '../domain/inventory_ledger_service.dart';
import '../sync/sync_outbox.dart';
import 'stock_reference_model.dart';

/// Ejecuta el subconjunto LOCAL/REMOTE de una secuencia sobre SQLite real
/// y compara contra el modelo de referencia (misma proyección de eventos).
class StockRealHarness {
  StockRealHarness({required this.tmpDir});

  final Directory tmpDir;
  final _ledger = InventoryLedgerService.instance;
  final Map<String, int> _codigoToId = {};

  Future<void> open(Map<String, int> seedStock) async {
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmpDir.path, 'cert.db'),
    );
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final e in seedStock.entries) {
      final id = await db.insert('productos', {
        'codigo': e.key,
        'descripcion': e.key,
        'stock': e.value,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': now,
      });
      _codigoToId[e.key] = id;
    }
  }

  Future<void> close() async {
    await DatabaseHelper.instance.cerrar();
  }

  Future<Map<String, int>> stocks() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('productos', columns: ['codigo', 'stock']);
    return {
      for (final r in rows)
        r['codigo']!.toString(): (r['stock'] as num).toInt(),
    };
  }

  Future<bool> allProjectionsOk() async {
    for (final id in _codigoToId.values) {
      if (!await _ledger.verificarProyeccion(id)) return false;
    }
    return true;
  }

  Future<int> outboxPendingCount() async {
    return SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending);
  }

  /// Aplica solo eventos locales/remotos (cloud simulado aparte en ref).
  Future<void> applyLocalish(StockCertEvent e) async {
    switch (e) {
      case LocalApply(:final eventId, :final codigo, :final delta, :final documentType):
        await _apply(eventId, codigo, delta, documentType, enqueue: true);
      case LocalReplay(:final eventId, :final codigo, :final delta):
        await _apply(eventId, codigo, delta, 'replay', enqueue: true);
      case RemoteApply(:final opId, :final codigo, :final delta):
        final id = _codigoToId[codigo];
        if (id == null) return;
        await _ledger.applyRemoteStockOp(
          opId: opId,
          productoId: id,
          codigo: codigo,
          delta: delta,
          notify: false,
        );
      default:
        break;
    }
  }

  Future<bool> _apply(
    String eventId,
    String codigo,
    int delta,
    String documentType, {
    required bool enqueue,
  }) async {
    final id = _codigoToId[codigo];
    if (id == null) return false;
    if (delta == 0) return false;
    final db = await DatabaseHelper.instance.database;
    final event = DomainEvent(
      eventId: eventId,
      type: DomainEventType.ajusteInventario,
      aggregateType: documentType,
      aggregateId: eventId,
      createdBy: 'cert',
      payload: {
        'documentType': documentType,
        'documentId': eventId,
        'motivo': documentType,
        'lines': [
          InventoryLine(productoId: id, cantidad: delta.abs()).toJson(),
        ],
      },
    );
    return db.transaction((txn) async {
      return _ledger.applyInTxn(
        txn,
        event,
        sign: delta < 0 ? -1 : 1,
        movimientoTipo: delta < 0 ? 'salida' : 'entrada',
        enqueueOutboundStockOps: enqueue,
        enforceStockPolicy: false,
      );
    });
  }
}

/// Filtra eventos locales de una secuencia para el harness SQLite +
/// construye el estado ref equivalente (solo local/remote, sin cloud).
StockRefState reduceLocalOnly(
  StockReferenceModel model,
  StockRefState initial,
  Iterable<StockCertEvent> events,
) {
  final localEvents = events.where(
    (e) =>
        e is LocalApply ||
        e is LocalReplay ||
        e is RemoteApply ||
        e is CrashBeforeCommit ||
        e is CrashAfterCommit,
  );
  return model.reduceAll(initial, localEvents);
}
