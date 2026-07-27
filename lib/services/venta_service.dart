import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../core/config/device_identity.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/domain/document_stock_reversal_policy.dart';
import '../core/domain/inventory_delivery_policy.dart';
import '../core/domain/inventory_ledger_service.dart';
import '../core/domain/money_ledger_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/stable_document_id.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import 'auth_service.dart';
import 'cuenta_corriente_service.dart';
import 'document_numbering_service.dart';

class VentaService {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final CuentaCorrienteService _cc = CuentaCorrienteService();

  // ── Número correlativo ────────────────────────────────────────────────────
  Future<String> siguienteNumero(String tipo) async {
    final db = await _db.database;
    final numbering = DocumentNumberingService.instance;
    final prefix = numbering.prefijo(tipo);
    final forzado = numbering.proximoForzado(tipo);
    final rows = await db.rawQuery(
      "SELECT MAX(CAST(SUBSTR(numero, ${prefix.length + 2}) AS INTEGER)) as max "
      "FROM ventas WHERE tipo = ? AND numero LIKE ?",
      [tipo, '$prefix-%'],
    );
    final maxDb = (rows.first['max'] as int?) ?? 0;
    final next = forzado > maxDb ? forzado : maxDb + 1;
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<int> crear(
    Venta venta,
    List<VentaItem> items, {
    double montoAbonado = 0,
    String medioPago = 'efectivo',
    String observacionesPago = '',
  }) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.crear,
      operacion: 'crear venta',
    );
    final id = await _cc.crearVentaConPago(
      venta: venta,
      items: items,
      montoAbonado: montoAbonado,
      medioPago: medioPago,
      observacionesPago: observacionesPago,
    );
    FirestoreSyncService.instance.programarSubidaVenta(id);
    DataRefreshHub.instance.notifyVentas();
    return id;
  }

  Future<List<Venta>> obtenerTodas({String? tipo}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      ${tipo != null ? 'WHERE v.tipo = ?' : ''}
      ORDER BY v.fecha DESC, v.id DESC
    ''', tipo != null ? [tipo] : []);
    return rows.map(Venta.fromMap).toList();
  }

  Future<Venta?> obtenerPorId(int id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.nombre AS clienteNombre
      FROM ventas v
      LEFT JOIN clientes c ON c.id = v.clienteId
      WHERE v.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Venta.fromMap(rows.first);
  }

  Future<List<VentaItem>> obtenerItems(int ventaId) async {
    final db = await _db.database;
    final rows = await db.query(
      'ventas_items',
      where: 'ventaId = ?',
      whereArgs: [ventaId],
    );
    return rows.map(VentaItem.fromMap).toList();
  }

  Future<int> _ledgerNetVenta(DatabaseExecutor txn, int ventaId) async {
    final r = await txn.rawQuery(
      "SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger "
      "WHERE document_type = 'venta' AND document_id = ?",
      ['$ventaId'],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  /// Anula venta: estado + reverso de stock (si el ledger neto entregó) + money
  /// en la misma TX. Idempotente si ya está anulada.
  Future<void> anular(int id, {bool syncAfter = true}) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.anular,
      operacion: 'anular venta',
    );
    DomainBootstrap.ensureInitialized();
    final db = await _db.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;

    int? clienteId;
    DomainEvent? invRevEvent;

    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT v.*, c.nombre AS clienteNombre
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.id = ?
      ''', [id]);
      if (rows.isEmpty) return;
      final venta = Venta.fromMap(rows.first);
      if (venta.estado == 'anulada') return;

      clienteId = venta.clienteId;
      final saldoAntes = venta.saldoPendiente;

      final itemRows = await txn.query(
        'ventas_items',
        where: 'ventaId = ?',
        whereArgs: [id],
      );
      final invLines = <Map<String, dynamic>>[];
      for (final item in itemRows) {
        final productoId = (item['productoId'] as num?)?.toInt();
        if (productoId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad == 0) continue;
        invLines.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      // net<0: entrega atribuida. net==0 solo si el tipo entrega (seguidor).
      final net = await _ledgerNetVenta(txn, id);
      final debeRevertirStock =
          DocumentStockReversalPolicy.shouldReverseOnAnular(
        ledgerNet: net,
        hasLines: invLines.isNotEmpty,
        treatZeroNetAsDelivered: venta.mueveStock,
      );

      await txn.update(
        'ventas',
        {
          'estado': 'anulada',
          'saldoPendiente': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (debeRevertirStock) {
        invRevEvent = DomainEvent(
          eventId: InventoryDeliveryPolicy.eventIdEntregaRevVenta(id, rev: rev),
          type: DomainEventType.mercaderiaEntregaRevertida,
          aggregateType: 'venta',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'venta',
            'documentId': stableCommercialDocumentId(numero: venta.numero, localId: id, fallbackPrefix: 'v_'),
            'documentNumero': venta.numero,
            'motivo': 'Reverso entrega venta ${venta.numero}',
            'lines': invLines,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          invRevEvent!,
          sign: 1,
          movimientoTipo: 'entrada',
        );
      }

      if (venta.clienteId != null && saldoAntes > 0.009) {
        await MoneyLedgerService.instance.appendInTxn(
          txn,
          event: DomainEvent(
            eventId: 'money:venta_cc_rev:$id:$rev',
            type: DomainEventType.ventaCcRevertida,
            aggregateType: 'venta',
            aggregateId: '$id',
            createdBy: user,
            payload: {
              'clienteId': venta.clienteId,
              'ventaId': id,
              'monto': saldoAntes,
              'motivo': 'Anulación venta ${venta.numero}',
            },
          ),
          accountType: 'cliente_cc',
          accountId: '${venta.clienteId}',
          delta: -saldoAntes.abs(),
          reason: 'Anulación venta ${venta.numero}',
          documentType: 'venta',
          documentId: '$id',
        );
      }
    });

    if (invRevEvent != null) {
      InventoryLedgerService.instance
          .enqueueCloudAfterApply(invRevEvent!, sign: 1);
      await DomainEventBus.instance.publish(invRevEvent!);
    }

    if (clienteId != null) {
      await _cc.recalcularSaldoCliente(clienteId!);
    }
    if (syncAfter) {
      FirestoreSyncService.instance.programarSubidaVenta(id);
    }
    DataRefreshHub.instance.notifyVentas();
    DataRefreshHub.instance.notifyStock();
  }

  /// Restaura una venta anulada: reabre estado/CC y re-entrega stock si aplica.
  /// Todo vía ledger (nunca write absoluto). Ciclos anular↔restaurar son seguros.
  Future<void> restaurar(int id, {bool syncAfter = true}) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.anular,
      operacion: 'restaurar venta',
    );
    DomainBootstrap.ensureInitialized();
    final db = await _db.database;
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;

    int? clienteId;
    DomainEvent? invEvent;

    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT v.*, c.nombre AS clienteNombre
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.id = ?
      ''', [id]);
      if (rows.isEmpty) {
        throw StateError('Venta no encontrada');
      }
      final venta = Venta.fromMap(rows.first);
      if (venta.estado != 'anulada') {
        throw StateError('Solo se pueden restaurar ventas anuladas');
      }

      clienteId = venta.clienteId;
      final saldo = (venta.total - venta.totalPagado).clamp(0, venta.total).toDouble();
      final estadoPago = saldo <= 0.009
          ? 'cobrado'
          : (venta.totalPagado > 0.009 ? 'parcial' : 'pendiente');

      final itemRows = await txn.query(
        'ventas_items',
        where: 'ventaId = ?',
        whereArgs: [id],
      );
      final invLines = <Map<String, dynamic>>[];
      for (final item in itemRows) {
        final productoId = (item['productoId'] as num?)?.toInt();
        if (productoId == null) continue;
        final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
        if (cantidad == 0) continue;
        invLines.add(InventoryLine(
          productoId: productoId,
          cantidad: cantidad,
        ).toJson());
      }

      // Re-entrega solo si el tipo entrega O hubo entrega histórica (legado),
      // y el neto del documento no indica entrega ya activa (anti doble).
      final entregaCanon = await txn.query(
        'domain_events',
        columns: ['event_id'],
        where: "event_id = ? OR event_id LIKE ?",
        whereArgs: [
          InventoryDeliveryPolicy.eventIdEntregaVenta(id),
          'inv:entrega:venta:$id:%',
        ],
        limit: 1,
      );
      final net = await _ledgerNetVenta(txn, id);
      final candidata = invLines.isNotEmpty &&
          (venta.mueveStock || entregaCanon.isNotEmpty);
      final debeEntregar = candidata &&
          DocumentStockReversalPolicy.shouldRedeliverOnRestore(
            ledgerNet: net,
            hasLines: invLines.isNotEmpty,
          );

      await txn.update(
        'ventas',
        {
          'estado': 'confirmada',
          'saldoPendiente': saldo,
          'estadoPago': estadoPago,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (debeEntregar) {
        invEvent = DomainEvent(
          eventId:
              InventoryDeliveryPolicy.eventIdEntregaRestoreVenta(id, rev: rev),
          type: DomainEventType.mercaderiaEntregada,
          aggregateType: 'venta',
          aggregateId: '$id',
          createdBy: user,
          deviceId: tag,
          payload: {
            'documentType': 'venta',
            'documentId': stableCommercialDocumentId(numero: venta.numero, localId: id, fallbackPrefix: 'v_'),
            'documentNumero': venta.numero,
            'motivo': 'Restauración entrega venta ${venta.numero}',
            'lines': invLines,
          },
        );
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          invEvent!,
          sign: -1,
          movimientoTipo: 'salida',
        );
      }

      if (venta.clienteId != null && saldo > 0.009) {
        await MoneyLedgerService.instance.appendInTxn(
          txn,
          event: DomainEvent(
            eventId: 'money:venta_cc:restore:$id:$rev',
            type: DomainEventType.ventaCargadaCc,
            aggregateType: 'venta',
            aggregateId: '$id',
            createdBy: user,
            payload: {
              'clienteId': venta.clienteId,
              'ventaId': id,
              'total': venta.total,
              'saldo': saldo,
              'motivo': 'Restauración venta ${venta.numero} a cuenta',
            },
          ),
          accountType: 'cliente_cc',
          accountId: '${venta.clienteId}',
          delta: saldo.abs(),
          reason: 'Restauración venta ${venta.numero} a cuenta',
          documentType: 'venta',
          documentId: '$id',
        );
      }
    });

    if (invEvent != null) {
      InventoryLedgerService.instance.enqueueCloudAfterApply(invEvent!, sign: -1);
      await DomainEventBus.instance.publish(invEvent!);
    }

    if (clienteId != null) {
      await _cc.recalcularSaldoCliente(clienteId!);
    }
    if (syncAfter) {
      FirestoreSyncService.instance.programarSubidaVenta(id);
    }
    DataRefreshHub.instance.notifyVentas();
    DataRefreshHub.instance.notifyStock();
  }

  Future<void> actualizarEstadoPago(int id, String estadoPago) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.editar,
      operacion: 'cambiar estado de pago venta',
    );
    final db = await _db.database;
    final venta = await obtenerPorId(id);
    if (venta == null) return;

    double totalPagado = venta.totalPagado;
    double saldo = venta.saldoPendiente;
    if (estadoPago == 'cobrado') {
      totalPagado = venta.total;
      saldo = 0;
    } else if (estadoPago == 'pendiente') {
      totalPagado = 0;
      saldo = venta.total;
    } else if (estadoPago == 'parcial' && totalPagado <= 0) {
      totalPagado = venta.total / 2;
      saldo = venta.total - totalPagado;
    }

    await db.update(
      'ventas',
      {
        'estadoPago': estadoPago,
        'totalPagado': totalPagado,
        'saldoPendiente': saldo,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (venta.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta.clienteId!);
    }
    FirestoreSyncService.instance.programarSubidaVenta(id);
    DataRefreshHub.instance.notifyVentas();
  }

  Future<void> actualizarAfip(
    int id, {
    required String estadoAfip,
    String cae = '',
    DateTime? caeVencimiento,
    int puntoVenta = 0,
  }) async {
    AuthorizationService.instance.require(
      AuthModules.remitos,
      AuthzAction.editar,
      operacion: 'actualizar AFIP venta',
    );
    final db = await _db.database;
    await db.update(
      'ventas',
      {
        'estadoAfip': estadoAfip,
        'cae': cae,
        'caeVencimiento': caeVencimiento?.toIso8601String(),
        'puntoVenta': puntoVenta,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    FirestoreSyncService.instance.programarSubidaVenta(id);
  }

  /// Anula (si hace falta) y borra la venta. Nunca hard-delete sin reverso.
  Future<void> eliminar(int id) async {
    final auth = AuthorizationService.instance;
    if (!auth.puede(AuthModules.remitos, AuthzAction.eliminar) &&
        !auth.puede(AuthModules.remitos, AuthzAction.anular)) {
      auth.require(
        AuthModules.remitos,
        AuthzAction.eliminar,
        operacion: 'eliminar venta',
      );
    }
    final db = await _db.database;
    final venta = await obtenerPorId(id);
    if (venta == null) return;

    if (venta.estado != 'anulada') {
      await anular(id, syncAfter: false);
    }

    syncInBackground(
      FirestoreSyncService.instance.eliminarVentaRemota(venta),
      tag: 'eliminarVentaRemota',
    );

    await db.transaction((txn) async {
      await txn.delete('pagos', where: 'ventaId = ?', whereArgs: [id]);
      await txn.delete('ventas_items', where: 'ventaId = ?', whereArgs: [id]);
      await txn.delete('ventas', where: 'id = ?', whereArgs: [id]);
    });

    if (venta.clienteId != null) {
      await _cc.recalcularSaldoCliente(venta.clienteId!);
    }
    DataRefreshHub.instance.notifyVentas();
    DataRefreshHub.instance.notifyStock();
  }
}
