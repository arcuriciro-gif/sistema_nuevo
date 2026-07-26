import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — fast-safe', () {
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

    test('throttle interactivo es más corto que el normal', () {
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThan(WindowsSyncPolicy.throttleDelayNormal.inMilliseconds),
      );
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThanOrEqualTo(200),
      );
    });

    test('soft pull prioriza productos (~50% de ticks)', () {
      final lanes = List.generate(24, WindowsSyncPolicy.softPullLane);
      final productos =
          lanes.where((l) => l.startsWith('productos_')).length;
      expect(productos, 12);

      // Alterna inc/cat en ticks pares.
      expect(WindowsSyncPolicy.softPullLane(0), 'productos_inc');
      expect(WindowsSyncPolicy.softPullLane(2), 'productos_cat');
      expect(WindowsSyncPolicy.softPullLane(4), 'productos_inc');

      // Impares: round-robin del resto.
      expect(WindowsSyncPolicy.softPullLane(1), 'clientes');
      expect(WindowsSyncPolicy.softPullLane(3), 'ventas');
      expect(WindowsSyncPolicy.softPullLane(5), 'remitos');
      expect(WindowsSyncPolicy.softPullLane(7), 'stock_ops');
      expect(WindowsSyncPolicy.softPullLane(9), 'compras');
      expect(WindowsSyncPolicy.softPullLane(11), 'proveedores');
      expect(WindowsSyncPolicy.softPullLane(13), 'clientes');
    });
  });
}
