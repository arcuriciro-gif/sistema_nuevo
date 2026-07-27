import 'package:sqflite/sqflite.dart';

import '../../../database/database_helper.dart';

/// Muestra puntual para historial 24h del panel.
class SyncMetricsSample {
  SyncMetricsSample({
    required this.at,
    required this.pendingL1,
    required this.pendingL2,
    required this.pendingL3,
    required this.pendingL4,
    required this.opsPerMin,
    required this.avgLatencyMs,
    required this.maxLatencyMs,
    required this.errors,
    required this.turbo,
    required this.firestoreOk,
  });

  final String at;
  final int pendingL1;
  final int pendingL2;
  final int pendingL3;
  final int pendingL4;
  final double opsPerMin;
  final double avgLatencyMs;
  final double maxLatencyMs;
  final int errors;
  final bool turbo;
  final bool firestoreOk;

  /// verde / amarillo / rojo según backlog L1 y errores.
  String get healthColor {
    if (errors > 5 || pendingL1 > 20 || !firestoreOk) return 'rojo';
    if (pendingL1 > 0 || pendingL2 > 10 || avgLatencyMs > 1500) {
      return 'amarillo';
    }
    return 'verde';
  }

  Map<String, dynamic> toMap() => {
        'at': at,
        'pending_l1': pendingL1,
        'pending_l2': pendingL2,
        'pending_l3': pendingL3,
        'pending_l4': pendingL4,
        'ops_per_min': opsPerMin,
        'avg_latency_ms': avgLatencyMs,
        'max_latency_ms': maxLatencyMs,
        'errors': errors,
        'turbo': turbo ? 1 : 0,
        'firestore_ok': firestoreOk ? 1 : 0,
      };

  static SyncMetricsSample fromMap(Map<String, dynamic> m) => SyncMetricsSample(
        at: m['at']?.toString() ?? '',
        pendingL1: (m['pending_l1'] as num?)?.toInt() ?? 0,
        pendingL2: (m['pending_l2'] as num?)?.toInt() ?? 0,
        pendingL3: (m['pending_l3'] as num?)?.toInt() ?? 0,
        pendingL4: (m['pending_l4'] as num?)?.toInt() ?? 0,
        opsPerMin: (m['ops_per_min'] as num?)?.toDouble() ?? 0,
        avgLatencyMs: (m['avg_latency_ms'] as num?)?.toDouble() ?? 0,
        maxLatencyMs: (m['max_latency_ms'] as num?)?.toDouble() ?? 0,
        errors: (m['errors'] as num?)?.toInt() ?? 0,
        turbo: ((m['turbo'] as num?)?.toInt() ?? 0) == 1,
        firestoreOk: ((m['firestore_ok'] as num?)?.toInt() ?? 0) == 1,
      );
}

class SyncMetricsHistoryStore {
  SyncMetricsHistoryStore._();
  static final SyncMetricsHistoryStore instance = SyncMetricsHistoryStore._();

  Future<Database> get _db async => DatabaseHelper.instance.database;

  Future<void> record(SyncMetricsSample sample) async {
    final db = await _db;
    await db.insert('sync_metrics_samples', sample.toMap());
    // Retener ~7 días (muestras ~1/min → tope ~12k; cleanup por fecha).
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    await db.delete(
      'sync_metrics_samples',
      where: 'at < ?',
      whereArgs: [cutoff],
    );
  }

  Future<List<SyncMetricsSample>> lastHours(int hours, {int limit = 500}) async {
    final db = await _db;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: hours))
        .toIso8601String();
    final rows = await db.query(
      'sync_metrics_samples',
      where: 'at >= ?',
      whereArgs: [cutoff],
      orderBy: 'at DESC',
      limit: limit,
    );
    return rows.map(SyncMetricsSample.fromMap).toList();
  }

  Future<List<SyncMetricsSample>> last24h({int limit = 288}) =>
      lastHours(24, limit: limit);

  Future<List<SyncMetricsSample>> last7d({int limit = 2000}) =>
      lastHours(24 * 7, limit: limit);
}
