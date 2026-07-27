import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_circuit_breaker.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_flight_recorder.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_observability_hub.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_op_trace.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_sla_monitor.dart';
import 'package:sistema_nuevo/core/sync/scheduler/adaptive_sync_controller.dart';

void main() {
  setUp(() {
    SyncObservabilityHub.instance.resetForTests();
    AdaptiveSyncController.instance.resetForTests();
  });

  group('Sync Engine 2.1 — Flight Recorder', () {
    test('capacidad circular 1000', () {
      final fr = SyncFlightRecorder.instance;
      for (var i = 0; i < 1200; i++) {
        fr.record(kind: 't', message: 'e$i');
      }
      expect(fr.last(n: 2000).length, SyncFlightRecorder.capacity);
      expect(fr.last(n: 1).single.message, 'e1199');
    });
  });

  group('Sync Engine 2.1 — Traces + SLA', () {
    test('percentiles y cumplimiento', () {
      final hub = SyncObservabilityHub.instance;
      for (var i = 0; i < 100; i++) {
        final id = 'upsert:venta:sla_$i';
        hub.onEnqueue(opId: id, entityType: 'venta', localId: i);
        hub.onClaimed(id);
        hub.onSendStart(id);
        hub.onSendDone(id, latencyMs: 10 + (i % 5), error: false);
        // Forzar timestamps consistentes en totalMs vía marcas ya hechas.
      }
      final stats = SyncSlaMonitor.instance.statsFor('venta');
      expect(stats.n, greaterThan(0));
      expect(stats.p50, isNotNull);
      expect(stats.p95, isNotNull);
      expect(stats.p99, isNotNull);
      expect(stats.max, isNotNull);
      expect(stats.avg, isNotNull);
      expect(stats.withinSlaPct, greaterThanOrEqualTo(95));
    });

    test('desglose wait/network/process', () {
      final t = SyncOpTrace(opId: 'x', entityType: 'venta');
      final now = DateTime.now().toUtc();
      t.createdAt = now.subtract(const Duration(milliseconds: 100));
      t.enqueuedAt = now.subtract(const Duration(milliseconds: 90));
      t.claimedAt = now.subtract(const Duration(milliseconds: 50));
      t.sendStartedAt = now.subtract(const Duration(milliseconds: 40));
      t.firestoreDoneAt = now.subtract(const Duration(milliseconds: 10));
      t.ackedAt = now;
      expect(t.waitMs, greaterThan(0));
      expect(t.networkMs, greaterThan(0));
      expect(t.totalMs, greaterThan(0));
      expect(t.processMs, isNotNull);
    });
  });

  group('Sync Engine 2.1 — Circuit Breaker', () {
    test('abre tras fallos consecutivos y reduce batch', () {
      final cb = SyncCircuitBreaker.instance;
      final a = AdaptiveSyncController.instance;
      a.batchL1 = 20;
      a.batchBackground = 40;
      for (var i = 0; i < SyncCircuitBreaker.openAfterFailures; i++) {
        cb.recordFailure(latencyMs: 100);
      }
      expect(cb.state, CircuitState.open);
      expect(cb.allowRequest(), isFalse);
      expect(a.batchL1, 4);
      expect(a.batchBackground, 4);
      expect(cb.tripCount, 1);
      expect(cb.extraWaitMs, greaterThan(0));
    });

    test('half-open → closed con éxitos', () {
      final cb = SyncCircuitBreaker.instance;
      for (var i = 0; i < SyncCircuitBreaker.openAfterFailures; i++) {
        cb.recordFailure(latencyMs: 50);
      }
      expect(cb.state, CircuitState.open);
      // Forzar cool-down vencido.
      cb.openedAt = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
      expect(cb.allowRequest(), isTrue);
      expect(cb.state, CircuitState.halfOpen);
      for (var i = 0; i < SyncCircuitBreaker.halfOpenSuccessesToClose; i++) {
        cb.recordSuccess(latencyMs: 20);
      }
      expect(cb.state, CircuitState.closed);
    });
  });
}
