import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — solo salida EXE', () {
    test('outboundOnlyPump y sin inbound automático', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isTrue);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isFalse);
      expect(WindowsSyncPolicy.healEveryNTicks, 0);
      expect(WindowsSyncPolicy.microCatchupEveryNTicks, 0);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, 0);
      expect(WindowsSyncPolicy.pollRemitosEveryNTicks, 0);
      expect(WindowsSyncPolicy.skipHeavyBootMaintenance, isTrue);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isTrue);
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
    });

    test('pump espaciado + hardCap 1', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        greaterThanOrEqualTo(100),
      );
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(1));
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        greaterThanOrEqualTo(30),
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

    test('Actualizar ahora Windows: local-only (anti-crash campo)', () {
      expect(WindowsSyncPolicy.manualRefreshPushOnly, isTrue);
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
      expect(WindowsSyncPolicy.outboundOnlyPump, isTrue);
      final m = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      expect(m.stockMaxApply, lessThanOrEqualTo(1));
      expect(m.pullClientes, isFalse);
    });
  });
}
