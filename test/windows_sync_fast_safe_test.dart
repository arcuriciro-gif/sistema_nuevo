import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — sync simple comercio chico (1.4.49)', () {
    test('automática: listeners + soft-pull, sin solo-salida', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isTrue);
      expect(WindowsSyncPolicy.skipProductosInitialSnapshotApply, isTrue);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isFalse);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThan(0));
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('botón manual desactivado (flags local-only)', () {
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
      expect(WindowsSyncPolicy.manualRefreshPushOnly, isTrue);
    });

    test('lanes incluyen productos_inc y productos_cat', () {
      final lanes = <String>{
        for (var i = 0; i < 24; i++)
          WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      };
      expect(lanes.contains('productos_inc'), isTrue);
      expect(lanes.contains('productos_cat'), isTrue);
    });

    test('Storage upload deshabilitado en Windows', () {
      expect(
        WindowsSyncPolicy.disableRemoteMediaAndChatListeners(
          isWindowsDesktop: true,
        ),
        isTrue,
      );
    });

    test('hardCap stock_ops ≤ 4', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
    });
  });
}
