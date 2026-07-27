import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_policy.dart';

/// Escenarios de estrés de política (sin I/O) — 500k / 2M / multi-device.
void main() {
  test('500.000 productos en fondo no bloquean 1 venta', () {
    final plan = SyncSchedulerPolicy.planLevels(
      pendingL1: 1,
      pendingL2: 0,
      pendingL3: 500000,
      pendingL4: 0,
      isWindows: false,
    );
    expect(plan.l1, 1);
    expect(plan.l3, 0);
    expect(plan.turboActive, isFalse);
  });

  test('2.000.000 movimientos stock L1 drenan antes que fondo', () {
    final plan = SyncSchedulerPolicy.planLevels(
      pendingL1: 2000000,
      pendingL2: 0,
      pendingL3: 100000,
      pendingL4: 0,
      isWindows: false,
    );
    expect(plan.l1, greaterThan(0));
    expect(plan.l3 + plan.l4, 0);
  });

  test('20 dispositivos: cada uno prioriza su L1 local', () {
    // Simula 20 schedulers independientes con misma policy.
    for (var d = 0; d < 20; d++) {
      final plan = SyncSchedulerPolicy.planLevels(
        pendingL1: 3,
        pendingL2: 5,
        pendingL3: 50000,
        pendingL4: 200,
        isWindows: d.isEven,
      );
      expect(plan.l1, greaterThan(0));
      expect(plan.l3, 0);
    }
  });

  test('internet lento: adaptive batch se pasa a planLevels', () {
    final slow = SyncSchedulerPolicy.planLevels(
      pendingL1: 0,
      pendingL2: 0,
      pendingL3: 10000,
      pendingL4: 0,
      isWindows: false,
      adaptiveBatchL1: 4,
      adaptiveBatchBg: 6,
    );
    final fast = SyncSchedulerPolicy.planLevels(
      pendingL1: 0,
      pendingL2: 0,
      pendingL3: 10000,
      pendingL4: 0,
      isWindows: false,
      adaptiveBatchL1: 30,
      adaptiveBatchBg: 50,
    );
    expect(slow.l3, lessThan(fast.l3));
    expect(slow.turboActive && fast.turboActive, isTrue);
  });

  test('import enorme + venta: shouldPreempt', () {
    expect(
      SyncSchedulerPolicy.shouldPreemptBackground(pendingL1: 1),
      isTrue,
    );
    expect(
      SyncSchedulerPolicy.shouldPreemptBackground(pendingL1: 0),
      isFalse,
    );
  });
}
