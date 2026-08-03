import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/sync_tombstone.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

void main() {
  group('Windows anti-crash invariants', () {
    test('solo salida: sin inbound en pump', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isTrue);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, 0);
      expect(WindowsSyncPolicy.pollRemitosEveryNTicks, 0);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isFalse);
      expect(WindowsSyncPolicy.skipHeavyBootMaintenance, isTrue);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isTrue);
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
    });

    test('hardCap stock_ops ≤ 1', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(1));
      final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      expect(b.maxApply, lessThanOrEqualTo(1));
      expect(b.recentLimit, 0);
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
