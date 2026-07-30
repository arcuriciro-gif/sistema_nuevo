import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';

void main() {
  test('stockOpCloudId incluye deviceId para no colisionar entre cajas', () {
    final a = DomainEvent(
      eventId: 'inv:entrega:remito:1',
      type: DomainEventType.mercaderiaEntregada,
      aggregateType: 'remito',
      aggregateId: '1',
      payload: const {},
      createdAt: DateTime.utc(2026, 1, 1),
      deviceId: 'ABCD',
    );
    final b = DomainEvent(
      eventId: 'inv:entrega:remito:1',
      type: DomainEventType.mercaderiaEntregada,
      aggregateType: 'remito',
      aggregateId: '1',
      payload: const {},
      createdAt: DateTime.utc(2026, 1, 1),
      deviceId: 'EFGH',
    );
    final idA = InventoryLedgerService.stockOpCloudId(a, 42);
    final idB = InventoryLedgerService.stockOpCloudId(b, 42);
    expect(idA, 'ABCD_inv:entrega:remito:1_42');
    expect(idB, 'EFGH_inv:entrega:remito:1_42');
    expect(idA, isNot(idB));
  });

  test('stockOpCloudId sin device cae a local_', () {
    final e = DomainEvent(
      eventId: 'inv:ajuste:9',
      type: DomainEventType.ajusteInventario,
      aggregateType: 'producto',
      aggregateId: '9',
      payload: const {},
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(
      InventoryLedgerService.stockOpCloudId(e, 7),
      'local_inv:ajuste:9_7',
    );
  });
}
