import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/sync_tombstone.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

void main() {
  group('Windows anti-crash invariants', () {
    test('hardCap stock_ops ≤ 1', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(1));
      for (final pending in [0, 5, 20, 80, 500]) {
        final b =
            WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: pending);
        expect(
          b.maxApply,
          lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
        );
        expect(b.recentLimit, 0);
      }
    });

    test('supervivencia: soft-pull/heal/listeners OFF', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        greaterThanOrEqualTo(80),
      );
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isFalse);
      expect(WindowsSyncPolicy.healEveryNTicks, 0);
      expect(WindowsSyncPolicy.microCatchupEveryNTicks, 0);
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
      expect(WindowsSyncPolicy.softPullProductosPageSize, lessThanOrEqualTo(6));
      final primer = WindowsSyncPolicy.windowsPrimerPullProductos();
      expect(primer.maxPages * primer.pageSize, lessThanOrEqualTo(6));
    });

    test('soft-pull lanes sin negocio/stock_ops', () {
      expect(
        WindowsSyncPolicy.softPullOtherLanes,
        isNot(contains('remitos')),
      );
      expect(
        WindowsSyncPolicy.softPullOtherLanes,
        isNot(contains('stock_ops')),
      );
      final lanes = List.generate(
        12,
        (i) => WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      );
      expect(lanes, isNot(contains('remitos')));
      expect(lanes, isNot(contains('ventas')));
      expect(lanes, isNot(contains('stock_ops')));
    });
  });

  group('Tombstone papelera (borrar definitivo)', () {
    test('tombstone:true con descripción → esTombstoneRemoto', () {
      final p = Producto.fromFirestore({
        'codigo': 'SKU-1',
        'descripcion': 'Suela que no debe quedar en papelera',
        'tombstone': true,
        'deletedAt': '2026-08-01T12:00:00.000Z',
        'marca': '',
        'categoria': '',
        'proveedor': '',
        'ubicacion': '',
        'stock': 0,
        'costo': 0,
        'precio': 0,
        'observaciones': '',
        'foto': '',
      });
      expect(p.tombstoneFlag, isTrue);
      expect(p.descripcion, isEmpty);
      expect(p.esTombstoneRemoto, isTrue);
      expect(p.estaEliminado, isTrue);
    });

    test('soft-delete con descripción NO es tombstone', () {
      final p = Producto.fromFirestore({
        'codigo': 'SKU-2',
        'descripcion': 'En papelera',
        'deleted_at': '2026-08-01T12:00:00.000Z',
        'marca': '',
        'categoria': '',
        'proveedor': '',
        'ubicacion': '',
        'stock': 0,
        'costo': 0,
        'precio': 0,
        'observaciones': '',
        'foto': '',
      });
      expect(p.esTombstoneRemoto, isFalse);
      expect(p.estaEliminado, isTrue);
    });

    test('payload producto limpia descripcion', () {
      final t = buildTombstonePayload(
        opId: 'delete:producto:X',
        deletedBy: 'u1',
        clearDescripcion: true,
      );
      expect(t['tombstone'], isTrue);
      expect(t['descripcion'], '');
    });
  });
}
