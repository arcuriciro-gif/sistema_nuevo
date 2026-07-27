import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/scheduler/sync_priority.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_policy.dart';

void main() {
  group('SyncSchedulerPolicy', () {
    test('con críticos pendientes el fondo no monopoliza', () {
      final plan = SyncSchedulerPolicy.planTick(
        pendingCritical: 50,
        pendingBackground: 100000,
        isWindows: false,
        pendingL1: 50,
        pendingL2: 0,
        pendingL3: 100000,
        pendingL4: 0,
      );
      expect(plan.criticalClaim, greaterThan(0));
      expect(plan.backgroundClaim, 0);
      expect(plan.criticalTypes, contains('venta'));
      expect(plan.backgroundTypes, contains('producto'));
    });

    test('sin críticos el fondo usa cupo turbo', () {
      final plan = SyncSchedulerPolicy.planTick(
        pendingCritical: 0,
        pendingBackground: 500,
        isWindows: true,
        pendingL1: 0,
        pendingL2: 0,
        pendingL3: 500,
        pendingL4: 0,
      );
      expect(plan.criticalClaim, 0);
      expect(plan.turboActive, isTrue);
      expect(plan.backgroundClaim, greaterThanOrEqualTo(4));
    });

    test('mustPreferCritical si hay backlog crítico', () {
      expect(
        SyncSchedulerPolicy.mustPreferCritical(
          pendingCritical: 1,
          pendingBackground: 99999,
        ),
        isTrue,
      );
      expect(
        SyncSchedulerPolicy.mustPreferCritical(
          pendingCritical: 0,
          pendingBackground: 99999,
        ),
        isFalse,
      );
    });

    test('coalesce solo metadata segura', () {
      expect(
        SyncSchedulerPolicy.shouldCoalesceUpsert(
          entityType: 'producto',
          operation: 'upsert',
        ),
        isTrue,
      );
      expect(
        SyncSchedulerPolicy.shouldCoalesceUpsert(
          entityType: 'venta',
          operation: 'upsert',
        ),
        isFalse,
      );
      expect(
        SyncPriority.canCoalesce('stock_op', 'upsert'),
        isFalse,
      );
    });
  });

  group('SyncPriority', () {
    test('ventas/remitos/stock son L1; clientes L2', () {
      expect(SyncPriority.forEntityType('venta'), SyncPriority.critical);
      expect(SyncPriority.forEntityType('remito'), SyncPriority.critical);
      expect(SyncPriority.forEntityType('stock_op'), SyncPriority.critical);
      expect(SyncPriority.isLevel1('cliente'), isFalse);
      expect(SyncPriority.isCriticalEntity('cliente'), isTrue);
      expect(SyncPriority.isCriticalEntity('producto'), isFalse);
      expect(SyncLane.forEntityType('venta'), SyncLane.critical);
      expect(SyncLane.forEntityType('cliente'), SyncLane.high);
      expect(SyncLane.forEntityType('producto'), SyncLane.normal);
    });
  });
}
