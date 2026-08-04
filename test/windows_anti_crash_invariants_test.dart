import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/sync_tombstone.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

void main() {
  group('Windows anti-crash invariants', () {
    test('1.4.52: sin listeners; soft-pull ON; stock_ops acotado', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isFalse);
      expect(WindowsSyncPolicy.skipProductosInitialSnapshotApply, isTrue);
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThan(0));
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
      expect(WindowsSyncPolicy.papeleraReconcileLimit, lessThanOrEqualTo(25));
    });

    test('hardCap stock_ops ≤ 3 (idle) / ≤ 2 (normal const)', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(2));
      expect(WindowsSyncPolicy.stockOpsHardCapIdle, lessThanOrEqualTo(3));
      final idle = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      expect(idle.maxApply, lessThanOrEqualTo(3));
      final busy = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 40);
      expect(busy.maxApply, lessThanOrEqualTo(2));
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
      expect(t['actualizadoEn'], isNotEmpty);
    });
  });
}
