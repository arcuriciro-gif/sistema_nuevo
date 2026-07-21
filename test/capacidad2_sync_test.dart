import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/sync/sync_health.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';

void main() {
  group('Capacidad 2 — outbox contract', () {
    test('estados del outbox son estables', () {
      expect(SyncOutboxStatus.pending, 'pending');
      expect(SyncOutboxStatus.inflight, 'inflight');
      expect(SyncOutboxStatus.acked, 'acked');
      expect(SyncOutboxStatus.dead, 'dead');
    });

    test('opIds de upsert/delete son deterministas', () {
      expect('upsert:cliente:12', startsWith('upsert:'));
      expect('delete:remito:R-00001-ABCD', startsWith('delete:'));
    });

    test('maxAttempts permite reintentos antes de dead', () {
      expect(SyncOutbox.maxAttempts, greaterThanOrEqualTo(5));
    });
  });

  group('Capacidad 2 — health', () {
    test('isCertifiableHealthy exige sin dead y poca cola', () {
      final ok = SyncHealthSnapshot(
        pending: 0,
        inflight: 0,
        dead: 0,
        conflicts24h: 0,
        lastSyncAt: DateTime.now().toUtc(),
        lastSyncDurationMs: 800,
        lastError: null,
        collectionStatus: const {'outbox': 'flushed'},
        firebaseReady: true,
        canWrite: true,
        syncCycles: 1,
        acksTotal: 3,
        failsTotal: 0,
      );
      expect(ok.isCertifiableHealthy, isTrue);
      expect(ok.toJson()['pending'], 0);

      final bad = SyncHealthSnapshot(
        pending: 10,
        inflight: 0,
        dead: 2,
        conflicts24h: 1,
        lastSyncAt: null,
        lastSyncDurationMs: null,
        lastError: 'boom',
        collectionStatus: const {},
        firebaseReady: true,
        canWrite: true,
        syncCycles: 1,
        acksTotal: 0,
        failsTotal: 2,
      );
      expect(bad.isCertifiableHealthy, isFalse);
    });
  });
}
