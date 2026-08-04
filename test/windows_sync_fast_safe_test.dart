import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — 1.4.51 anti-crash + wipe', () {
    test('sin listener productos; soft-pull ON', () {
      expect(WindowsSyncPolicy.enableProductosListenerWindows, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.papeleraReconcileLimit, lessThanOrEqualTo(40));
      expect(WindowsSyncPolicy.stockOpsHardCap, lessThanOrEqualTo(2));
    });

    test('listeners negocio ON', () {
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });
  });
}
