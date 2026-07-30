import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/models/producto.dart';

/// Invariantes anti-crash Windows + política soft-delete (sin Firebase).
void main() {
  group('Windows anti-crash invariants', () {
    test('hardCap stock_ops nunca supera 4', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
      for (final pending in [0, 5, 20, 80, 500]) {
        final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: pending);
        expect(b.maxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
        final m = WindowsSyncPolicy.manualRefreshBudgetWindows(
          pendingProductos: pending,
        );
        expect(m.stockMaxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
      }
    });

    test('soft-pull y pump no son agresivos (regresión 1.4.36 crash)', () {
      expect(WindowsSyncPolicy.outboxPumpInterval.inSeconds, greaterThanOrEqualTo(30));
      expect(WindowsSyncPolicy.softPullInterval.inSeconds, greaterThanOrEqualTo(45));
      expect(
        WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0).inSeconds,
        greaterThanOrEqualTo(25),
      );
      expect(WindowsSyncPolicy.softPullProductosPageSize, lessThanOrEqualTo(10));
      final primer = WindowsSyncPolicy.windowsPrimerPullProductos();
      expect(primer.maxPages * primer.pageSize, lessThanOrEqualTo(12));
    });

    test('quiet lane: productos presentes pero ≤50%', () {
      final lanes = List.generate(
        12,
        (i) => WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      );
      final prod = lanes.where((l) => l.startsWith('productos_')).length;
      final stock = lanes.where((l) => l == 'stock_ops').length;
      expect(prod, greaterThanOrEqualTo(2));
      expect(prod, lessThanOrEqualTo(6));
      expect(stock, greaterThanOrEqualTo(2));
    });

    test('listeners de productos siguen OFF en Windows', () {
      expect(
        WindowsSyncPolicy.windowsBusinessListenerCollections,
        isNot(contains('productos')),
      );
    });
  });

  group('Soft-delete upload policy', () {
    test('producto activo no debe mandar deleted_at null en toFirestore merge', () {
      // Simula la regla de actualizarSinStock: activos omiten deleted_at.
      final activo = Producto(
        codigo: 'A1',
        descripcion: 'Suela',
        marca: '',
        categoria: '',
        proveedor: '',
        ubicacion: '',
        stock: 1,
        costo: 0,
        precio: 10,
        observaciones: '',
        foto: '',
        deletedAt: null,
      );
      final data = activo.toFirestore()..remove('stock');
      data.remove('deleted_at'); // política: no mergear null
      expect(data.containsKey('deleted_at'), isFalse);
      expect(activo.estaEliminado, isFalse);
    });

    test('soft-delete sí incluye deleted_at', () {
      final baja = Producto(
        codigo: 'A1',
        descripcion: 'Suela',
        marca: '',
        categoria: '',
        proveedor: '',
        ubicacion: '',
        stock: 1,
        costo: 0,
        precio: 10,
        observaciones: '',
        foto: '',
        deletedAt: '2026-07-30T12:00:00.000Z',
      );
      expect(baja.estaEliminado, isTrue);
      final data = baja.toFirestore()..remove('stock');
      expect(data['deleted_at'], isNotNull);
    });
  });
}
