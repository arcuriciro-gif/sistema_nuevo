import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — 1.4.52 anti-crash + zona oculta', () {
    test('sin listeners productos/negocio; soft-pull ON', () {
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.papeleraReconcileLimit, lessThanOrEqualTo(25));
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(2));
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isFalse,
      );
    });

    test('lane papelera existe en soft-pull', () {
      final lanes = List.generate(
        12,
        (i) => WindowsSyncPolicy.softPullLane(i, prioritizeStockOps: true),
      );
      expect(lanes, contains('papelera'));
    });
  });
}
