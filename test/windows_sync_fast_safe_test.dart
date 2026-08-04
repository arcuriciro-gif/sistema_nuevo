import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — automática sin tumbar botón', () {
    test('listeners negocio ON; productos por soft-pull', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isFalse);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isFalse);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThan(0));
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('botón Actualizar = solo local (anti-crash campo)', () {
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
      expect(WindowsSyncPolicy.manualRefreshPushOnly, isTrue);
    });

    test('pump frecuente + catálogo en lanes', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        lessThanOrEqualTo(30),
      );
      final lanes = <String>{
        for (var i = 0; i < 16; i++)
          WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      };
      expect(lanes.contains('productos_inc'), isTrue);
      expect(lanes.contains('productos_cat'), isTrue);
      expect(lanes.contains('remitos'), isTrue);
    });

    test('Storage/chat remoto deshabilitados en Windows', () {
      expect(
        WindowsSyncPolicy.disableRemoteMediaAndChatListeners(
          isWindowsDesktop: true,
        ),
        isTrue,
      );
    });

    test('hardCap stock_ops ≤ 4', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
      final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      expect(b.maxApply, lessThanOrEqualTo(4));
    });
  });
}
