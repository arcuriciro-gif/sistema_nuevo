import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/sync_tombstone.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

void main() {
  group('Windows anti-crash invariants', () {
    test('sync simple: listeners + soft-pull; sin snapshot 10k', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isTrue);
      expect(WindowsSyncPolicy.skipProductosInitialSnapshotApply, isTrue);
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThan(0));
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isFalse);
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('hardCap stock_ops ≤ 4', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
      final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      expect(b.maxApply, lessThanOrEqualTo(4));
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
