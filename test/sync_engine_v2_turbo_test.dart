import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/scheduler/adaptive_sync_controller.dart';
import 'package:sistema_nuevo/core/sync/scheduler/entity_lock_registry.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_priority.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_policy.dart';
import 'package:sistema_nuevo/core/sync/scheduler/turbo_mode_controller.dart';

void main() {
  setUp(() {
    AdaptiveSyncController.instance.resetForTests();
    TurboModeController.instance.resetForTests();
    EntityLockRegistry.instance.resetForTests();
  });

  group('Sync Engine 2.0 — 4 niveles', () {
    test('mapeo de entidades a niveles', () {
      expect(SyncPriority.levelForEntityType('venta'), SyncPriorityLevel.critical);
      expect(SyncPriority.levelForEntityType('stock_op'), SyncPriorityLevel.critical);
      expect(SyncPriority.levelForEntityType('cliente'), SyncPriorityLevel.high);
      expect(SyncPriority.levelForEntityType('producto'), SyncPriorityLevel.normal);
      expect(SyncPriority.levelForEntityType('branding'), SyncPriorityLevel.background);
      expect(SyncPriority.isLevel1('venta'), isTrue);
      expect(SyncPriority.isLevel1('cliente'), isFalse);
      expect(SyncPriority.isCriticalEntity('cliente'), isTrue);
    });

    test('Turbo: L1 vacío → capacidad plena a L3/L4', () {
      final plan = SyncSchedulerPolicy.planLevels(
        pendingL1: 0,
        pendingL2: 0,
        pendingL3: 80000,
        pendingL4: 100,
        isWindows: false,
      );
      expect(plan.turboActive, isTrue);
      expect(plan.mode, 'turbo');
      expect(plan.l3, greaterThan(10));
      expect(plan.l1, 0);
    });

    test('Preemption: aparece L1 → fondo a 0', () {
      final plan = SyncSchedulerPolicy.planLevels(
        pendingL1: 1,
        pendingL2: 0,
        pendingL3: 80000,
        pendingL4: 500,
        isWindows: false,
      );
      expect(plan.turboActive, isFalse);
      expect(plan.mode, 'focused');
      expect(plan.l1, 1);
      expect(plan.l3, 0);
      expect(plan.l4, 0);
      expect(
        SyncSchedulerPolicy.shouldPreemptBackground(pendingL1: 1),
        isTrue,
      );
    });

    test('TurboModeController registra preemption', () {
      final turbo = TurboModeController.instance;
      turbo.evaluate(
        pendingL1: 0,
        pendingL2: 0,
        pendingL3: 1000,
        pendingL4: 0,
        isWindows: true,
      );
      expect(turbo.active, isTrue);
      turbo.evaluate(
        pendingL1: 2,
        pendingL2: 0,
        pendingL3: 1000,
        pendingL4: 0,
        isWindows: true,
      );
      expect(turbo.active, isFalse);
      expect(turbo.preemptionCount, greaterThanOrEqualTo(1));
    });

    test('Adaptive: alta latencia encoge batch', () {
      final a = AdaptiveSyncController.instance;
      final before = a.batchBackground;
      for (var i = 0; i < 5; i++) {
        a.recordSample(latencyMs: 3000, error: true);
      }
      expect(a.batchBackground, lessThan(before));
      expect(a.batchL1, lessThanOrEqualTo(10));
    });

    test('Adaptive: red sana crece batch', () {
      final a = AdaptiveSyncController.instance;
      for (var i = 0; i < 8; i++) {
        a.recordSample(latencyMs: 120, error: false);
      }
      expect(a.batchBackground, greaterThanOrEqualTo(20));
    });

    test('EntityLock evita doble claim misma entidad', () {
      final locks = EntityLockRegistry.instance;
      expect(locks.tryAcquire('producto', '1'), isTrue);
      expect(locks.tryAcquire('producto', '1'), isFalse);
      locks.release('producto', '1');
      expect(locks.tryAcquire('producto', '1'), isTrue);
    });

    test('planTick compat con 500k fondo + críticos', () {
      final plan = SyncSchedulerPolicy.planTick(
        pendingCritical: 5,
        pendingBackground: 500000,
        isWindows: false,
        pendingL1: 5,
        pendingL2: 0,
        pendingL3: 500000,
        pendingL4: 0,
      );
      expect(plan.criticalClaim, 5);
      expect(plan.backgroundClaim, 0);
      expect(plan.turboActive, isFalse);
    });

    test('coalesce nunca en ventas/stock', () {
      expect(
        SyncSchedulerPolicy.shouldCoalesceUpsert(
          entityType: 'venta',
          operation: 'upsert',
        ),
        isFalse,
      );
      expect(
        SyncSchedulerPolicy.shouldCoalesceUpsert(
          entityType: 'producto',
          operation: 'upsert',
        ),
        isTrue,
      );
    });
  });
}
