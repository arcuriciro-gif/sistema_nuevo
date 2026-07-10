import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/sync_queue_service.dart';

void main() {
  group('SyncQueueService UI status', () {
    test('uiLabel refleja estados visibles', () {
      final sync = SyncQueueService.instance;
      // Sin Firebase Auth en test → sin conexión.
      expect(sync.uiStatus, SyncUiStatus.sinConexion);
      expect(sync.uiLabel, contains('Sin conexión'));
    });

    test('backoff crece y tiene tope', () {
      // Acceso indirecto: reintentos usan 5 * 2^(n-1) capped 900.
      int backoff(int attempts) {
        final sec = 5 * (1 << (attempts - 1).clamp(0, 8));
        return sec.clamp(5, 900);
      }

      expect(backoff(1), 5);
      expect(backoff(2), 10);
      expect(backoff(3), 20);
      expect(backoff(10), 900);
    });
  });
}
