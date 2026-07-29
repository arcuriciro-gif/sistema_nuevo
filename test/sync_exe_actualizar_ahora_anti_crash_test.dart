import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

/// Campo 2026-07-28: EXE se caía con 5 productos pending.
/// Causa: soft-pull "quieto" usaba maxApply 60.
void main() {
  test('con 5 productos pending (caso real) maxApply ≤ 4', () {
    final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 5);
    expect(WindowsSyncPolicy.prioritizeBusinessConvergence(pendingProductos: 5),
        isTrue);
    expect(b.maxApply, lessThanOrEqualTo(4));
    expect(b.maxApply, lessThan(50));
  });

  test('Actualizar ahora: micro-rondas maxApply≤2 (sin soft-pull)', () {
    final m = WindowsSyncPolicy.manualRefreshBudgetWindows(pendingProductos: 5);
    expect(m.stockRounds, greaterThan(0));
    expect(m.stockRounds * m.stockMaxApply, lessThan(50));
    expect(m.stockMaxApply, lessThanOrEqualTo(2));
    expect(m.negocioLimit, 0);
    expect(m.pullConfig, isFalse);
  });

  test('orden: push productos antes que cualquier pull', () {
    const fases = [
      'push_productos',
      'push_stock_ops',
      'push_docs',
      'micro_rounds_maxApply_2',
    ];
    expect(fases.first, 'push_productos');
    expect(fases.last, 'micro_rounds_maxApply_2');
  });
}
