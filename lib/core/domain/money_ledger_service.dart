import 'package:flutter/foundation.dart';

import '../../database/database_helper.dart';
import '../events/data_refresh_hub.dart';
import 'domain_event.dart';
import 'event_bus.dart';

/// Ledger de dinero append-only (CC / pagos) — Capacidad 3.
class MoneyLedgerService {
  MoneyLedgerService._();
  static final MoneyLedgerService instance = MoneyLedgerService._();

  bool _registered = false;

  void registerHandlers() {
    if (_registered) return;
    _registered = true;
    final bus = DomainEventBus.instance;
    bus.subscribe(DomainEventType.ventaCargadaCc, _onVentaCc);
    bus.subscribe(DomainEventType.ventaCcRevertida, _onVentaCcRevertida);
    bus.subscribe(DomainEventType.pagoRegistrado, _onPago);
    bus.subscribe(DomainEventType.pagoAnulado, _onPagoAnulado);
  }

  @visibleForTesting
  void resetForTests() {
    _registered = false;
  }

  Future<void> _onVentaCc(DomainEvent e) async {
    final clienteId = (e.payload['clienteId'] as num?)?.toInt();
    // Cargo el total de la venta; los pagos restan en PAGO_REGISTRADO.
    final monto = (e.payload['total'] as num?)?.toDouble() ??
        (e.payload['saldo'] as num?)?.toDouble() ??
        0;
    if (clienteId == null || monto == 0) return;
    await _append(
      event: e,
      accountType: 'cliente_cc',
      accountId: '$clienteId',
      delta: monto.abs(),
      reason: e.payload['motivo']?.toString() ?? 'Venta a cuenta',
      documentType: 'venta',
      documentId: e.payload['ventaId']?.toString(),
    );
  }

  Future<void> _onVentaCcRevertida(DomainEvent e) async {
    final clienteId = (e.payload['clienteId'] as num?)?.toInt();
    final monto = (e.payload['monto'] as num?)?.toDouble() ??
        (e.payload['saldo'] as num?)?.toDouble() ??
        0;
    if (clienteId == null || monto == 0) return;
    await _append(
      event: e,
      accountType: 'cliente_cc',
      accountId: '$clienteId',
      delta: -monto.abs(),
      reason: e.payload['motivo']?.toString() ?? 'Venta CC revertida',
      documentType: 'venta',
      documentId: e.payload['ventaId']?.toString(),
    );
  }

  Future<void> _onPago(DomainEvent e) async {
    final clienteId = (e.payload['clienteId'] as num?)?.toInt();
    final monto = (e.payload['monto'] as num?)?.toDouble() ?? 0;
    if (clienteId == null || monto == 0) return;
    await _append(
      event: e,
      accountType: 'cliente_cc',
      accountId: '$clienteId',
      delta: -monto.abs(),
      reason: e.payload['motivo']?.toString() ?? 'Pago',
      documentType: 'pago',
      documentId: e.payload['pagoId']?.toString(),
    );
  }

  Future<void> _onPagoAnulado(DomainEvent e) async {
    final clienteId = (e.payload['clienteId'] as num?)?.toInt();
    final monto = (e.payload['monto'] as num?)?.toDouble() ?? 0;
    if (clienteId == null || monto == 0) return;
    await _append(
      event: e,
      accountType: 'cliente_cc',
      accountId: '$clienteId',
      delta: monto.abs(),
      reason: e.payload['motivo']?.toString() ?? 'Pago anulado',
      documentType: 'pago',
      documentId: e.payload['pagoId']?.toString(),
    );
  }

  Future<void> _append({
    required DomainEvent event,
    required String accountType,
    required String accountId,
    required double delta,
    required String reason,
    String? documentType,
    String? documentId,
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
      debugPrint('MoneyLedger: skip idempotent ${event.eventId}');
      return;
    }

    final prev = await reconstruirSaldo(accountType, accountId);
    final after = prev + delta;

    await db.transaction((txn) async {
      await txn.insert('domain_events', event.toRow());
      await txn.insert('money_ledger', {
        'event_id': event.eventId,
        'account_type': accountType,
        'account_id': accountId,
        'delta': delta,
        'currency': 'ARS',
        'reason': reason,
        'document_type': documentType,
        'document_id': documentId,
        'balance_after': after,
        'created_at': event.createdAt.toIso8601String(),
      });
    });
    DataRefreshHub.instance.notifyTodo();
  }

  Future<double> reconstruirSaldo(String accountType, String accountId) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) s FROM money_ledger '
      'WHERE account_type = ? AND account_id = ?',
      [accountType, accountId],
    );
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }
}
