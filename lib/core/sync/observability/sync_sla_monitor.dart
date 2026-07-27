import 'sync_op_trace.dart';

/// Percentiles SLA por entidad (ventana rolling de trazas completadas).
class SlaStats {
  SlaStats({
    required this.entityType,
    required this.n,
    required this.p50,
    required this.p90,
    required this.p95,
    required this.p99,
    required this.max,
    required this.avg,
    required this.slaTargetMs,
    required this.withinSlaPct,
  });

  final String entityType;
  final int n;
  final int? p50;
  final int? p90;
  final int? p95;
  final int? p99;
  final int? max;
  final double? avg;
  final int slaTargetMs;
  final double withinSlaPct;

  bool get meetsSla => n > 0 && withinSlaPct >= 95.0;

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'n': n,
        'p50': p50,
        'p90': p90,
        'p95': p95,
        'p99': p99,
        'max': max,
        'avg': avg,
        'slaTargetMs': slaTargetMs,
        'withinSlaPct': withinSlaPct,
        'meetsSla': meetsSla,
      };
}

class SyncSlaMonitor {
  SyncSlaMonitor._();
  static final SyncSlaMonitor instance = SyncSlaMonitor._();

  /// Objetivos (ms) — críticos 2s; precio/producto 30s.
  static const targets = <String, int>{
    'venta': 2000,
    'remito': 2000,
    'stock_op': 2000,
    'compra': 2000,
    'cuenta_corriente': 2000,
    'cliente': 2000,
    'proveedor': 5000,
    'producto': 30000,
  };

  static const tracked = [
    'venta',
    'stock_op',
    'cliente',
    'compra',
    'remito',
    'cuenta_corriente',
  ];

  SlaStats statsFor(String entityType) {
    final traces =
        SyncTraceRegistry.instance.completedForEntity(entityType, limit: 300);
    final xs = traces
        .map((t) => t.totalMs)
        .whereType<int>()
        .toList()
      ..sort();
    final target = targets[entityType] ?? 5000;
    if (xs.isEmpty) {
      return SlaStats(
        entityType: entityType,
        n: 0,
        p50: null,
        p90: null,
        p95: null,
        p99: null,
        max: null,
        avg: null,
        slaTargetMs: target,
        withinSlaPct: 100,
      );
    }
    int pct(int p) => xs[((xs.length - 1) * p / 100).round()];
    final within = xs.where((v) => v <= target).length * 100.0 / xs.length;
    final avg = xs.reduce((a, b) => a + b) / xs.length;
    return SlaStats(
      entityType: entityType,
      n: xs.length,
      p50: pct(50),
      p90: pct(90),
      p95: pct(95),
      p99: pct(99),
      max: xs.last,
      avg: avg,
      slaTargetMs: target,
      withinSlaPct: within,
    );
  }

  Map<String, dynamic> snapshot() {
    final by = <String, dynamic>{};
    for (final e in tracked) {
      by[e] = statsFor(e).toJson();
    }
    return {
      'byEntity': by,
      'overallMeetsSla': tracked.every((e) {
        final s = statsFor(e);
        return s.n == 0 || s.meetsSla;
      }),
    };
  }
}
