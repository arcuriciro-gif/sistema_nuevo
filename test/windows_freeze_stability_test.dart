import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';

/// Campo: EXE se cerraba solo ~2 min (listeners + soft-pull + pull productos).
void main() {
  test('freeze background ON: sin listeners ni soft-pull agresivo', () {
    expect(WindowsSyncPolicy.freezeBackgroundForStability, isTrue);
    expect(
      WindowsSyncPolicy.enableBusinessDocListeners(isWindowsDesktop: true),
      isFalse,
    );
    expect(
      WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0).inHours,
      greaterThanOrEqualTo(1),
    );
  });
}
