import 'dart:math' show max;

import '../sync_outbox.dart';
import '../scheduler/sync_scheduler.dart';
import 'sync_flight_recorder.dart';
import 'sync_observability_hub.dart';
import 'sync_sla_monitor.dart';

/// Benchmark local (outbox/scheduler). No sustituye hop Firebase real.
/// PDF se genera aparte (`sync_report_pdf`) para no cargar `package:pdf` en el shell.
class SyncBenchmarkReport {
  SyncBenchmarkReport(this.data);
  final Map<String, dynamic> data;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Sync Engine Benchmark')
      ..writeln()
      ..writeln('- at: ${data['at']}')
      ..writeln('- note: ${data['note']}')
      ..writeln();
    for (final e in (data['scenarios'] as Map).entries) {
      b.writeln('## ${e.key}');
      final m = e.value as Map;
      m.forEach((k, v) => b.writeln('- $k: $v'));
      b.writeln();
    }
    return b.toString();
  }
}

class SyncBenchmarkRunner {
  SyncBenchmarkRunner._();
  static final SyncBenchmarkRunner instance = SyncBenchmarkRunner._();

  Future<SyncBenchmarkReport> run({
    bool includeHeavy = false,
    bool includeVentas1000 = true,
  }) async {
    final scenarios = <String, Map<String, dynamic>>{};
    var cleaned = 0;
    try {
      scenarios['ventas_100'] = await _benchVentas(100);
      if (includeVentas1000) {
        scenarios['ventas_1000'] = await _benchVentas(1000);
      }
      if (includeHeavy) {
        scenarios['productos_10000_claim'] = await _benchProductosClaim(10000);
      } else {
        scenarios['productos_500_claim'] = await _benchProductosClaim(500);
      }
      scenarios['sla_snapshot'] = Map<String, dynamic>.from(
        SyncSlaMonitor.instance.snapshot(),
      );
    } finally {
      // Campo: sin esto el lab dejaba 500 productos pending → Panel AMARILLO.
      cleaned = await SyncOutbox.instance.ackLabBenchmarkGarbage();
      cleaned += await SyncOutbox.instance.ackOrphanUpserts();
    }

    SyncFlightRecorder.instance.record(
      kind: 'benchmark',
      message: 'completed',
      data: {
        'scenarios': scenarios.keys.toList(),
        'labCleanupAcked': cleaned,
      },
    );

    return SyncBenchmarkReport({
      'at': DateTime.now().toUtc().toIso8601String(),
      'note':
          'LAB: mide enqueue+claim+ack local. NO mide sync PC↔celular. '
          'Hop Firestore requiere piloto. Basura lab se limpia al terminar '
          '(acked=$cleaned).',
      'labCleanupAcked': cleaned,
      'scenarios': scenarios,
      'dashboard':
          await SyncObservabilityHub.instance.dashboardSnapshot(light: true),
    });
  }

  Future<Map<String, dynamic>> _benchVentas(int n) async {
    final sw = Stopwatch()..start();
    final lat = <int>[];
    for (var i = 1; i <= n; i++) {
      final opId = 'upsert:venta:bench_${n}_$i';
      final localId = SyncOutbox.labVentaLocalIdMin + i;
      SyncObservabilityHub.instance.onEnqueue(
        opId: opId,
        entityType: 'venta',
        localId: localId,
      );
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'venta',
        localId: localId,
      );
      final t0 = Stopwatch()..start();
      final claimed = await SyncOutbox.instance.claimBatch(
        limit: 1,
        entityTypes: const ['venta'],
        orderByPriority: true,
      );
      if (claimed.isEmpty) continue;
      final id = claimed.first['op_id'] as String;
      SyncObservabilityHub.instance.onClaimed(id);
      SyncObservabilityHub.instance.onSendStart(id);
      await SyncOutbox.instance.ack(id);
      SyncObservabilityHub.instance
          .onSendDone(id, latencyMs: t0.elapsedMilliseconds, error: false);
      lat.add(t0.elapsedMilliseconds);
    }
    sw.stop();
    lat.sort();
    int pct(int p) =>
        lat.isEmpty ? 0 : lat[((lat.length - 1) * p / 100).round()];
    return {
      'n': n,
      'total_ms': sw.elapsedMilliseconds,
      'p50_ms': pct(50),
      'p95_ms': pct(95),
      'p99_ms': pct(99),
      'max_ms': lat.isEmpty ? 0 : lat.last,
      'ops_per_sec': n * 1000.0 / max(1, sw.elapsedMilliseconds),
    };
  }

  Future<Map<String, dynamic>> _benchProductosClaim(int n) async {
    final sw = Stopwatch()..start();
    final capped = n.clamp(1, 500);
    for (var i = 1; i <= capped; i++) {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: SyncOutbox.labProductoLocalIdMin + i,
        forceBackground: true,
      );
    }
    await SyncOutbox.instance.enqueueUpsert(
      entityType: 'venta',
      localId: SyncOutbox.labVentaLocalIdMin,
    );
    final bd = await SyncOutbox.instance.pendingBreakdown();
    final claimed = await SyncScheduler.instance.claimForTick(
      breakdown: bd,
      isWindows: false,
    );
    sw.stop();
    // Devolver claimed a pending limpio vía cleanup global (finally del run).
    return {
      'n_productos': capped,
      'first_claim_type':
          claimed.isEmpty ? null : claimed.first['entity_type'],
      'elapsed_ms': sw.elapsedMilliseconds,
      'pass_critical_first':
          claimed.isNotEmpty && claimed.first['entity_type'] == 'venta',
    };
  }
}
