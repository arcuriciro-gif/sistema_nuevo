import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

void main() {
  group('WindowsSyncPolicy — 1.4.50 papelera/sin stock', () {
    test('sync automática sin solo-salida', () {
      expect(WindowsSyncPolicy.outboundOnlyPump, isFalse);
      expect(WindowsSyncPolicy.enablePeriodicSoftPull, isTrue);
      expect(WindowsSyncPolicy.skipPrimerPullProductos, isFalse);
      expect(WindowsSyncPolicy.skipProductosInitialSnapshotApply, isTrue);
      expect(
        WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
        isTrue,
      );
    });

    test('botón manual desactivado', () {
      expect(WindowsSyncPolicy.manualRefreshLocalOnly, isTrue);
    });

    test('productos_cat en rotación (papelera/lista)', () {
      final lanes = {
        for (var i = 0; i < 18; i++) WindowsSyncPolicy.softPullLane(i),
      };
      expect(lanes.contains('productos_cat'), isTrue);
      expect(lanes.contains('productos_inc'), isTrue);
    });
  });
}
