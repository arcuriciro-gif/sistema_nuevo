import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — supervivencia EXE', () {
    test('bulkSoloEncolar solo en Windows', () {
      expect(
        WindowsSyncPolicy.bulkSoloEncolar(isWindowsDesktop: true),
        isTrue,
      );
      expect(
        WindowsSyncPolicy.bulkSoloEncolar(isWindowsDesktop: false),
        isFalse,
      );
    });

    test('Storage/chat remoto deshabilitados en Windows', () {
      expect(
        WindowsSyncPolicy.disableRemoteMediaAndChatListeners(
          isWindowsDesktop: true,
        ),
        isTrue,
      );
    });

    test('pump supervivencia: espaciado, soft-pull/heal/catchup OFF', () {
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        greaterThanOrEqualTo(25),
      );
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        greaterThanOrEqualTo(80),
      );
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isFalse);
      expect(WindowsSyncPolicy.healEveryNTicks, 0);
      expect(WindowsSyncPolicy.microCatchupEveryNTicks, 0);
      expect(WindowsSyncPolicy.stockOpsEveryNTicks, greaterThanOrEqualTo(2));
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(1));
    });

    test('throttle interactivo es más corto que el normal', () {
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThan(WindowsSyncPolicy.throttleDelayNormal.inMilliseconds),
      );
    });

    test('listeners de negocio OFF en Windows', () {
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
      expect(WindowsSyncPolicy.pollRemitosEveryNTicks, greaterThan(0));
      expect(WindowsSyncPolicy.pollRemitosLimit, lessThanOrEqualTo(6));
    });

    test('soft pull lane (si se reactivara): sin stock_ops ni negocio', () {
      final lanes = List.generate(20, (i) => WindowsSyncPolicy.softPullLane(i));
      expect(lanes, isNot(contains('remitos')));
      expect(lanes, isNot(contains('ventas')));
      expect(lanes, isNot(contains('clientes')));
      expect(lanes, isNot(contains('compras')));
      expect(lanes, isNot(contains('stock_ops')));
      expect(
        WindowsSyncPolicy.softPullOtherLanes,
        isNot(contains('stock_ops')),
      );
    });

    test('budget stock_ops ≤ hardCap y sin recent dual-pull', () {
      final quiet = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      final busy = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 200);
      expect(quiet.maxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
      expect(busy.maxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
      expect(quiet.recentLimit, 0);
      expect(busy.recentLimit, 0);
    });

    test('Actualizar ahora Windows: micro, no tumba EXE', () {
      final m = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      expect(
        m.stockMaxApply,
        lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
      );
      expect(m.stockRounds * m.stockMaxApply, lessThanOrEqualTo(4));
      expect(m.pullClientes, isFalse);
      expect(m.yieldMs, greaterThanOrEqualTo(200));
      final catchup = WindowsSyncPolicy.windowsCatchupStockOpsBudget();
      expect(
        catchup.maxApply,
        lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
      );
    });
  });
}
