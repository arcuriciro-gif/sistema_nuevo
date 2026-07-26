import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — estable/rápido', () {
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
        lessThanOrEqualTo(120),
      );
    });

    test('intervalos razonables (no ultra-lentos)', () {
      expect(
        WindowsSyncPolicy.outboxPumpInterval.inSeconds,
        lessThanOrEqualTo(45),
      );
      expect(
        WindowsSyncPolicy.softPullInterval.inSeconds,
        lessThanOrEqualTo(90),
      );
      expect(
        WindowsSyncPolicy.reclaimStaleInflightAfter.inSeconds,
        greaterThanOrEqualTo(120),
      );
    });

    test('soft pull ~33% productos (estable)', () {
      final lanes = List.generate(30, WindowsSyncPolicy.softPullLane);
      final productos =
          lanes.where((l) => l.startsWith('productos_')).length;
      expect(productos, 10);

      expect(WindowsSyncPolicy.softPullLane(0), 'productos_inc');
      expect(WindowsSyncPolicy.softPullLane(3), 'productos_cat');
      expect(WindowsSyncPolicy.softPullLane(6), 'productos_inc');

      // Impares del ciclo: resto de colecciones.
      expect(WindowsSyncPolicy.softPullLane(1), isNot(startsWith('productos_')));
      expect(WindowsSyncPolicy.softPullLane(2), isNot(startsWith('productos_')));
    });
  });
}
