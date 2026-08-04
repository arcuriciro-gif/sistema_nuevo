import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — sync automática simple (21 jul)', () {
    test('listeners + soft-pull + inbound ON', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isTrue);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isFalse);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThan(0));
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('pump frecuente para convergencia en segundos', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        lessThanOrEqualTo(40),
      );
      expect(
        WindowsSyncPolicy.softPullInterval.inSeconds,
        lessThanOrEqualTo(40),
      );
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        lessThanOrEqualTo(25),
      );
    });

    test('Storage/chat remoto deshabilitados en Windows', () {
      expect(
        WindowsSyncPolicy.disableRemoteMediaAndChatListeners(
          isWindowsDesktop: true,
        ),
        isTrue,
      );
      expect(
        WindowsSyncPolicy.bulkSoloEncolar(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('Actualizar ahora opcional — no es el camino principal', () {
      expect(WindowsSyncPolicy.manualRefreshPushOnly, isFalse);
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isFalse);
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      final m = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      expect(m.stockMaxApply, lessThanOrEqualTo(4));
      expect(m.pullClientes, isTrue);
    });

    test('hardCap stock_ops ≤ 4 (anti-crash 1.4.20)', () {
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(4));
      final b = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      expect(b.maxApply, lessThanOrEqualTo(4));
    });
  });
}
