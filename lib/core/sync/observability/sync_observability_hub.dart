import 'dart:async' show unawaited;

import 'package:sqflite/sqflite.dart';

import '../../../database/database_helper.dart';
import '../scheduler/sync_scheduler.dart';
import '../sync_health.dart';
import 'sync_circuit_breaker.dart';
import 'sync_flight_recorder.dart';
import 'sync_op_trace.dart';
import 'sync_path_logger.dart';
import 'sync_sla_monitor.dart';

/// Fachada Sync Engine 2.1 — observabilidad sin cambiar el scheduler core.
///
/// No importa SyncOutbox (rompe ciclo outbox↔hub que puede tumbar el APK).
class SyncObservabilityHub {
  SyncObservabilityHub._();
  static final SyncObservabilityHub instance = SyncObservabilityHub._();

  final traces = SyncTraceRegistry.instance;
  final flight = SyncFlightRecorder.instance;
  final circuit = SyncCircuitBreaker.instance;
  final sla = SyncSlaMonitor.instance;
  final path = SyncPathLogger.instance;

  /// Evita persistir trazas en ráfaga (SQLite busy / OOM en Android bajo).
  bool _persistBusy = false;
  int _persistSkip = 0;

  void onEnqueue({
    required String opId,
    required String entityType,
    int? localId,
    String? remoteId,
  }) {
    try {
      traces.ensure(
        opId,
        entityType: entityType,
        entityLocalId: localId,
        entityRemoteId: remoteId,
      );
      traces.markEnqueued(opId);
      flight.record(
        kind: 'enqueue',
        message: 'enqueued $entityType',
        opId: opId,
        entityType: entityType,
      );
    } catch (_) {}
  }

  void onClaimed(String opId) {
    try {
      traces.markClaimed(opId);
      flight.record(kind: 'claim', message: 'claimed', opId: opId);
    } catch (_) {}
  }

  void onSendStart(String opId) {
    try {
      traces.markSendStart(opId);
    } catch (_) {}
  }

  void onSendDone(String opId, {required int latencyMs, required bool error}) {
    try {
      if (error) {
        traces.markAcked(opId, success: false);
        circuit.recordFailure(latencyMs: latencyMs);
        flight.record(
          kind: 'fail',
          message: 'send_fail ${latencyMs}ms',
          opId: opId,
        );
      } else {
        traces.markFirestoreDone(opId);
        traces.markAcked(opId, success: true);
        circuit.recordSuccess(latencyMs: latencyMs);
        flight.record(
          kind: 'ack',
          message: 'acked ${latencyMs}ms',
          opId: opId,
        );
      }
      // Persistir 1 de cada 5 acks para no saturar SQLite en el pump.
      _persistSkip++;
      if (_persistSkip >= 5) {
        _persistSkip = 0;
        unawaited(_persistTrace(opId));
      }
    } catch (_) {}
  }

  void onRemoteApplied({
    required String entityType,
    int? localId,
    String? remoteId,
  }) {
    try {
      traces.markRemoteApplied(
        entityType: entityType,
        entityLocalId: localId,
        entityRemoteId: remoteId,
      );
      flight.record(
        kind: 'remote_apply',
        message: 'applied $entityType',
        entityType: entityType,
        data: {'localId': localId, 'remoteId': remoteId},
      );
    } catch (_) {}
  }

  /// [light]: evita queries históricas pesadas (uso al abrir shell/admin).
  Future<Map<String, dynamic>> dashboardSnapshot({bool light = false}) async {
    final health = await SyncHealthService.instance.snapshot();
    final engine = SyncScheduler.instance.engineSnapshot();
    final metrics = (engine['metrics'] as Map?) ?? const {};

    int? oldestAgeSec;
    try {
      if (health.pendingPreview.isNotEmpty) {
        final u = health.pendingPreview.first['updated_at']?.toString();
        final at = u == null ? null : DateTime.tryParse(u);
        if (at != null) {
          oldestAgeSec = DateTime.now().toUtc().difference(at).inSeconds;
        }
      }
    } catch (_) {}

    const int? rss = null;

    final slaSnap = _slaDashboard();
    final history = light
        ? {
            'last1h': {'n': 0},
            'last24h': {'n': health.history24h.length},
            'last7d': {'n': 0},
          }
        : await _historyWindows();

    final color = health.healthColor;
    final status = color == 'verde'
        ? 'OK'
        : color == 'rojo'
            ? 'CRÍTICO'
            : 'DEGRADADO';

    return {
      'healthColor': color,
      'healthStatus': status,
      'pendingL1': health.pendingL1,
      'pendingL2': health.pendingL2,
      'pendingL3': health.pendingL3,
      'pendingL4': health.pendingL4,
      'pending': health.pending,
      'inflight': health.inflight,
      'dead': health.dead,
      'retries': health.failsTotal,
      'acks': health.acksTotal,
      'conflicts': health.conflicts24h,
      'conflicts24h': health.conflicts24h,
      'firebaseReady': health.firebaseReady,
      'canWrite': health.canWrite,
      'latencyAvgMs': (metrics['avgCriticalLatencyMs'] as num?)?.round(),
      'latencyP95Ms': slaSnap['globalP95Ms'],
      'throughputOpsPerMin': metrics['opsPerMinuteCritical'],
      'workers': const {'l1': 1, 'l2': 1, 'l3': 1, 'l4': 1},
      'circuitBreaker': circuit.snapshot(),
      'circuit': circuit.snapshot(),
      'sla': slaSnap,
      'schedulerMode': engine['mode'],
      'oldestPendingAgeSec': oldestAgeSec ?? 0,
      'rssBytes': rss,
      'history': history,
      'flightLast': light ? const <Map<String, dynamic>>[] : flight.dumpJson(n: 20),
      'at': DateTime.now().toUtc().toIso8601String(),
      'light': light,
    };
  }

  Map<String, dynamic> _slaDashboard() {
    final by = <String, dynamic>{};
    var weighted = 0.0;
    var weight = 0;
    final p95s = <int>[];
    for (final e in SyncSlaMonitor.tracked) {
      final s = sla.statsFor(e);
      by[e] = {
        ...s.toJson(),
        'p50Ms': s.p50,
        'p90Ms': s.p90,
        'p95Ms': s.p95,
        'p99Ms': s.p99,
        'compliancePct': s.withinSlaPct,
        'samples': s.n,
      };
      if (s.n > 0) {
        weighted += s.withinSlaPct * s.n;
        weight += s.n;
        if (s.p95 != null) p95s.add(s.p95!);
      }
    }
    p95s.sort();
    return {
      'byEntity': by,
      'overallCompliancePct': weight == 0 ? 100.0 : weighted / weight,
      'overallMeetsSla': SyncSlaMonitor.tracked.every((e) {
        final s = sla.statsFor(e);
        return s.n == 0 || s.meetsSla;
      }),
      'globalP95Ms':
          p95s.isEmpty ? null : p95s[((p95s.length - 1) * 0.95).round()],
    };
  }

  Future<Map<String, dynamic>> _historyWindows() async {
    return {
      'last1h': {'n': 0},
      'last24h': {'n': 0},
      'last7d': {'n': 0},
    };
  }


  Future<void> _persistTrace(String opId) async {
    if (_persistBusy) return;
    final t = traces.get(opId);
    if (t == null) return;
    _persistBusy = true;
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(
        'sync_op_traces',
        {
          'op_id': t.opId,
          'entity_type': t.entityType,
          'entity_local_id': t.entityLocalId,
          'entity_remote_id': t.entityRemoteId,
          'created_at': t.createdAt.toIso8601String(),
          'enqueued_at': t.enqueuedAt?.toIso8601String(),
          'claimed_at': t.claimedAt?.toIso8601String(),
          'send_started_at': t.sendStartedAt?.toIso8601String(),
          'firestore_done_at': t.firestoreDoneAt?.toIso8601String(),
          'acked_at': t.ackedAt?.toIso8601String(),
          'remote_applied_at': t.remoteAppliedAt?.toIso8601String(),
          'total_ms': t.totalMs,
          'success': t.success ? 1 : 0,
          'last_error': t.lastError,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) AS c FROM sync_op_traces'),
          ) ??
          0;
      if (count > 3000) {
        await db.rawDelete(
          'DELETE FROM sync_op_traces WHERE op_id IN ('
          'SELECT op_id FROM sync_op_traces ORDER BY created_at ASC LIMIT ?)',
          [count - 2000],
        );
      }
    } catch (_) {
    } finally {
      _persistBusy = false;
    }
  }

  void resetForTests() {
    traces.resetForTests();
    flight.resetForTests();
    circuit.resetForTests();
    path.resetForTests();
    _persistBusy = false;
    _persistSkip = 0;
  }
}
