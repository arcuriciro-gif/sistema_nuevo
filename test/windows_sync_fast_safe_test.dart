import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — cuarentena', () {
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

    test('cuarentena y pumps conservadores', () {
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        lessThanOrEqualTo(30),
      );
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        greaterThanOrEqualTo(40),
      );
      expect(
        WindowsSyncPolicy.softPullInterval.inSeconds,
        greaterThanOrEqualTo(60),
      );
    });

    test('throttle interactivo es más corto que el normal', () {
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThan(WindowsSyncPolicy.throttleDelayNormal.inMilliseconds),
      );
    });

    test('soft pull: stock + productos, sin negocio con listener', () {
      final lanes = List.generate(20, (i) => WindowsSyncPolicy.softPullLane(i));
      expect(lanes, isNot(contains('remitos')));
      expect(lanes, isNot(contains('ventas')));
      expect(lanes, isNot(contains('clientes')));
      expect(lanes, isNot(contains('compras')));
      expect(lanes.where((l) => l == 'stock_ops').length, greaterThanOrEqualTo(8));
      expect(
        lanes.where((l) => l == 'productos_inc').length,
        greaterThanOrEqualTo(4),
      );
      expect(WindowsSyncPolicy.softPullLane(0), 'stock_ops');
      expect(WindowsSyncPolicy.softPullLane(1), 'productos_inc');
    });

    test('soft pull incluye config (listas/permisos/branding texto)', () {
      expect(
        WindowsSyncPolicy.softPullOtherLanes,
        containsAll([
          'listas',
          'categorias',
          'permisos',
          'branding_text',
          'stock_ops',
        ]),
      );
    });

    test('con outbox quieto prioriza stock + productos sin ráfaga', () {
      expect(
        WindowsSyncPolicy.prioritizeBusinessConvergence(pendingProductos: 0),
        isTrue,
      );
      final lanes = List.generate(
        12,
        (i) => WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      );
      expect(lanes.where((l) => l == 'stock_ops').length, greaterThanOrEqualTo(4));
      expect(
        lanes.where((l) => l == 'productos_inc').length,
        greaterThanOrEqualTo(2),
      );
      expect(WindowsSyncPolicy.recentBusinessDocsLimit(pendingProductos: 0), 0);
      expect(
        WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0).inSeconds,
        greaterThanOrEqualTo(40),
      );
    });

    test('Windows habilita listeners solo de negocio (no productos)', () {
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
      expect(
        WindowsSyncPolicy.windowsBusinessListenerCollections,
        containsAll(['remitos', 'ventas', 'clientes', 'compras']),
      );
      expect(
        WindowsSyncPolicy.windowsBusinessListenerCollections,
        isNot(contains('productos')),
      );
    });

    test('budget stock_ops ≤ hardCap', () {
      final quiet = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      final busy = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 200);
      expect(quiet.maxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
      expect(busy.maxApply, lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap));
      expect(quiet.recentLimit, greaterThan(0));
      expect(busy.recentLimit, greaterThan(0));
    });

    test('Actualizar ahora Windows: micro, no tumba EXE', () {
      final m = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      expect(
        m.stockMaxApply,
        lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
      );
      expect(m.stockRounds * m.stockMaxApply, lessThanOrEqualTo(12));
      expect(m.pullClientes, isFalse);
      expect(m.yieldMs, greaterThanOrEqualTo(150));
      final catchup = WindowsSyncPolicy.windowsCatchupStockOpsBudget();
      expect(
        catchup.maxApply,
        lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
      );
    });
  });
}
