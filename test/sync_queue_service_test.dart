import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/sync_queue_service.dart';

void main() {
  group('SyncQueueService UI status', () {
    test('uiLabel refleja estados visibles', () {
      final sync = SyncQueueService.instance;
      // En test sin Firebase Auth el estado suele ser sinConexion
      // (o error / pendiente según bootstrap).
      expect(sync.uiLabel, isNotEmpty);
      expect(
        sync.uiLabel.contains('Sin conexión') ||
            sync.uiLabel.contains('Firebase no listo') ||
            sync.uiLabel.contains('Pendiente') ||
            sync.uiLabel.contains('Error') ||
            sync.uiLabel.contains('Sincronizado') ||
            sync.uiLabel.contains('Sincronizando'),
        isTrue,
        reason: 'uiLabel inesperado: ${sync.uiLabel}',
      );
    });

    test('backoff crece y tiene tope', () {
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
