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

    test('cuarentena da tiempo al UI antes de Firebase de colección', () {
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        greaterThanOrEqualTo(45),
      );
      expect(
        WindowsSyncPolicy.quarantineAfterLogin.inSeconds,
        lessThanOrEqualTo(120),
      );
    });

    test('throttle interactivo es más corto que el normal', () {
      expect(
        WindowsSyncPolicy.throttleDelayInteractive.inMilliseconds,
        lessThan(WindowsSyncPolicy.throttleDelayNormal.inMilliseconds),
      );
    });

    test('soft pull ~33% productos', () {
      final lanes = List.generate(30, WindowsSyncPolicy.softPullLane);
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
  });
}
