import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

/// Campo: EXE se cerraba ~1–2 min post-login con listeners+soft-pull+seed.
void main() {
  test('freezeBackgroundForStability ON — sin listeners ni soft-pull agresivo',
      () {
    expect(WindowsSyncPolicy.freezeBackgroundForStability, isTrue);
    expect(
      WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
      isFalse,
    );
    expect(
      WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0).inHours,
      greaterThanOrEqualTo(24),
    );
    expect(
      WindowsSyncPolicy.quarantineForBacklog(pendingProductos: 0).inSeconds,
      lessThanOrEqualTo(10),
    );
    expect(
      WindowsSyncPolicy.outboxPumpInterval.inSeconds,
      greaterThanOrEqualTo(40),
    );
    // Convergencia crítica SÍ existe (papelera + stock acotado).
    final b = WindowsSyncPolicy.criticalConvergenceBudget();
    expect(b.stockMaxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
    expect(b.productosRecientes, greaterThan(0));
  });

  test('stockOpsHardCap sigue ≤4 para Actualizar ahora', () {
    expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
    final b = WindowsSyncPolicy.manualRefreshBudgetWindows(
      pendingProductos: 0,
    );
    expect(b.stockMaxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
  });
}
