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
      expect(
        WindowsSyncPolicy.disableRemoteMediaAndChatListeners(
          isWindowsDesktop: false,
        ),
        isFalse,
      );
    });

    test('cuarentena corta; con backlog de productos aún más corta', () {
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        lessThanOrEqualTo(30),
      );
      expect(
        WindowsSyncPolicy.quarantineForBacklog(pendingProductos: 500).inSeconds,
        lessThanOrEqualTo(12),
      );
      expect(
        WindowsSyncPolicy.quarantineForBacklog(pendingProductos: 0).inSeconds,
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
      );
    });

    test('pump/pull más frecuentes para convergencia negocio', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        lessThanOrEqualTo(40),
      );
      expect(
        WindowsSyncPolicy.softPullInterval.inSeconds,
        lessThanOrEqualTo(90),
      );
    });

    test('outboxDrainPlan prioriza productos si hay cola (no tick=0 eterno)', () {
      final plan = WindowsSyncPolicy.outboxDrainPlan(
        breakdown: const {'producto': 350, 'proveedor': 4},
        tick: 0,
      );
      expect(plan, isNotEmpty);
      expect(plan.first.types, contains('producto'));
      expect(plan.first.claim, greaterThanOrEqualTo(8));
    });

    test('outboxDrainPlan vacío no inventa drains', () {
      final plan = WindowsSyncPolicy.outboxDrainPlan(
        breakdown: const {},
        tick: 1,
      );
      // tick%2==0 es false → sin docs; tick%3==2 false → sin stock
      expect(plan.where((s) => s.types.contains('producto')), isEmpty);
    });

    test('throttle interactivo es más corto que el normal', () {
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThan(WindowsSyncPolicy.throttleDelayNormal.inMilliseconds),
      );
    });

    test('soft pull ~33% productos', () {
      final lanes = List.generate(30, (i) => WindowsSyncPolicy.softPullLane(i));
      final productos =
          lanes.where((l) => l.startsWith('productos_')).length;
      expect(productos, 10);
      expect(WindowsSyncPolicy.softPullLane(0), 'productos_inc');
      expect(WindowsSyncPolicy.softPullLane(3), 'productos_cat');
    });

    test('soft pull incluye config (listas/permisos/branding texto)', () {
      expect(
        WindowsSyncPolicy.softPullOtherLanes,
        containsAll([
          'listas',
          'categorias',
          'permisos',
          'branding_text',
          'compras',
          'stock_ops',
        ]),
      );
    });

    test('con outbox quieto prioriza negocio (remitos/ventas/stock_ops)', () {
      expect(
        WindowsSyncPolicy.prioritizeBusinessConvergence(pendingProductos: 0),
        isTrue,
      );
      expect(
        WindowsSyncPolicy.prioritizeStockOpsPull(pendingProductos: 5),
        isTrue,
      );
      expect(
        WindowsSyncPolicy.prioritizeBusinessConvergence(pendingProductos: 6),
        isFalse,
      );
      final lanes = List.generate(
        12,
        (i) => WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      );
      expect(lanes.where((l) => l == 'remitos').length, greaterThanOrEqualTo(2));
      expect(lanes.where((l) => l == 'ventas').length, greaterThanOrEqualTo(2));
      expect(lanes.where((l) => l == 'stock_ops').length, greaterThanOrEqualTo(2));
      expect(
        WindowsSyncPolicy.softPullLane(0, prioritizeStockOps: true),
        'remitos',
      );
      expect(
        WindowsSyncPolicy.softPullLane(1, prioritizeStockOps: true),
        'ventas',
      );
      expect(
        WindowsSyncPolicy.recentBusinessDocsLimit(pendingProductos: 0),
        greaterThan(0),
      );
      expect(
        WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0).inSeconds,
        lessThan(WindowsSyncPolicy.softPullInterval.inSeconds),
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
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThanOrEqualTo(80),
      );
    });

    test('budget stock_ops crece solo con cola quieta', () {
      final quiet = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
      final busy = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 200);
      expect(quiet.maxApply, greaterThan(busy.maxApply));
      expect(quiet.recentLimit, greaterThan(0));
      expect(busy.recentLimit, 0);
    });
  });
}
