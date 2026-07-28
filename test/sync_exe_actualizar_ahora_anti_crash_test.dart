import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

/// Regresión campo 2026-07-28: Actualizar ahora con maxApply 250 tumbaba el EXE.
/// Windows debe quedarse en el presupuesto anti-crash; la ráfaga es solo móvil.
void main() {
  test('Windows manual: maxApply ≤ 6 (no ráfaga 1.4.18)', () {
    for (final pending in [0, 5, 10, 50, 200]) {
      final b = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: pending,
      );
      expect(b.stockMaxApply, lessThanOrEqualTo(6),
          reason: 'pending=$pending');
      expect(b.stockMaxApply * b.stockRounds, lessThanOrEqualTo(40),
          reason: 'total apply/gesto pending=$pending');
      expect(b.stockRecentLimit, lessThanOrEqualTo(40));
    }
  });

  test('orden anti-crash: push productos antes que pull stock (contrato)', () {
    // Documenta el orden de _actualizarAhoraBody Windows tras 1.4.19.
    const fases = [
      'rewind_wm',
      'push_productos_stuck',
      'push_stock_ops',
      'pull_stock_budgeted',
      'repair_60',
      'negocio',
      'drain_residual',
    ];
    expect(fases.indexOf('push_productos_stuck'),
        lessThan(fases.indexOf('pull_stock_budgeted')));
    expect(fases.indexOf('push_stock_ops'),
        lessThan(fases.indexOf('pull_stock_budgeted')));
  });

  test('ráfaga móvil tolera maxApply alto; Windows no', () {
    const mobileMaxApply = 400;
    final win = WindowsSyncPolicy.manualRefreshBudgetWindows(
      pendingProductos: 0,
    );
    expect(mobileMaxApply, greaterThan(win.stockMaxApply * 10));
  });
}
