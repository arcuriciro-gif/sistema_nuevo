import 'scheduler/sync_priority.dart';
import 'scheduler/sync_scheduler.dart';
import 'scheduler/sync_scheduler_metrics.dart';
import 'sync_outbox.dart';
import 'sync_watermark_store.dart';

/// Snapshot de salud Sync Engine 2.0.
class SyncHealthSnapshot {
  SyncHealthSnapshot({
    required this.pending,
    required this.inflight,
    required this.dead,
    required this.conflicts24h,
    required this.lastSyncAt,
    required this.lastSyncDurationMs,
    required this.lastError,
    required this.collectionStatus,
    required this.firebaseReady,
    required this.canWrite,
    required this.syncCycles,
    required this.acksTotal,
    required this.failsTotal,
    this.pendingByType = const {},
    this.pendingPreview = const [],
    this.pendingCritical = 0,
    this.pendingBackground = 0,
    this.pendingL1 = 0,
    this.pendingL2 = 0,
    this.pendingL3 = 0,
    this.pendingL4 = 0,
    this.scheduler = const {},
    this.engine = const {},
    this.avgSyncMs,
    this.healthColor = 'verde',
    this.history24h = const [],
  });

  final int pending;
  final int inflight;
  final int dead;
  final int conflicts24h;
  final DateTime? lastSyncAt;
  final int? lastSyncDurationMs;
  final String? lastError;
  final Map<String, String> collectionStatus;
  final bool firebaseReady;
  final bool canWrite;
  final int syncCycles;
  final int acksTotal;
  final int failsTotal;
  final Map<String, int> pendingByType;
  final List<Map<String, dynamic>> pendingPreview;
  final int pendingCritical;
  final int pendingBackground;
  final int pendingL1;
  final int pendingL2;
  final int pendingL3;
  final int pendingL4;
  final Map<String, dynamic> scheduler;
  final Map<String, dynamic> engine;
  final double? avgSyncMs;
  final String healthColor;
  final List<Map<String, dynamic>> history24h;

  String get pendingBreakdownLabel =>
      SyncOutbox.formatBreakdown(pendingByType);

  bool get isCertifiableHealthy =>
      dead == 0 &&
      pendingL1 == 0 &&
      pending < 500 &&
      (lastError == null || pending == 0);

  Map<String, dynamic> toJson() => {
        'pending': pending,
        'inflight': inflight,
        'dead': dead,
        'conflicts24h': conflicts24h,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'lastSyncDurationMs': lastSyncDurationMs,
        'lastError': lastError,
        'collectionStatus': collectionStatus,
        'firebaseReady': firebaseReady,
        'canWrite': canWrite,
        'syncCycles': syncCycles,
        'acksTotal': acksTotal,
        'failsTotal': failsTotal,
        'pendingByType': pendingByType,
        'pendingCritical': pendingCritical,
        'pendingBackground': pendingBackground,
        'pendingL1': pendingL1,
        'pendingL2': pendingL2,
        'pendingL3': pendingL3,
        'pendingL4': pendingL4,
        'scheduler': scheduler,
        'engine': engine,
        'avgSyncMs': avgSyncMs,
        'healthColor': healthColor,
        'isCertifiableHealthy': isCertifiableHealthy,
      };
}

class SyncHealthService {
  SyncHealthService._();
  static final SyncHealthService instance = SyncHealthService._();

  DateTime? lastSyncAt;
  int? lastSyncDurationMs;
  String? lastError;
  final Map<String, String> collectionStatus = {};
  int syncCycles = 0;
  int acksTotal = 0;
  int failsTotal = 0;
  bool firebaseReady = false;
  bool canWrite = false;

  final List<int> _syncDurationsMs = [];

  void markCollection(String name, String status) {
    collectionStatus[name] = status;
  }

  void recordCycle({required int durationMs, String? error}) {
    syncCycles++;
    lastSyncAt = DateTime.now().toUtc();
    lastSyncDurationMs = durationMs;
    lastError = error;
    _syncDurationsMs.add(durationMs);
    if (_syncDurationsMs.length > 50) {
      _syncDurationsMs.removeAt(0);
    }
  }

  void recordAck() => acksTotal++;
  void recordFail() => failsTotal++;

  double? get avgSyncMs {
    if (_syncDurationsMs.isEmpty) return null;
    final sum = _syncDurationsMs.fold<int>(0, (a, b) => a + b);
    return sum / _syncDurationsMs.length;
  }

  Future<SyncHealthSnapshot> snapshot() async {
    final counts = await SyncOutbox.instance.counts();
    final breakdown = await SyncOutbox.instance.pendingBreakdown();
    final preview = await SyncOutbox.instance.listPendingPreview(limit: 20);
    final byLane = await SyncOutbox.instance.pendingByLane();
    final conflicts = await SyncWatermarkStore.instance.conflictsSince(
      DateTime.now().toUtc().subtract(const Duration(hours: 24)),
    );
    final levels = SyncScheduler.countLevels(breakdown);
    var pendingCritical =
        (byLane[SyncLane.critical.wireName] ?? 0) +
        (byLane[SyncLane.high.wireName] ?? 0);
    var pendingBackground =
        (byLane[SyncLane.normal.wireName] ?? 0) +
        (byLane[SyncLane.background.wireName] ?? 0);
    if (pendingCritical + pendingBackground == 0 && breakdown.isNotEmpty) {
      pendingCritical = levels.l1 + levels.l2;
      pendingBackground = levels.l3 + levels.l4;
    }

    const List<Map<String, dynamic>> history = [];

    final engine = SyncScheduler.instance.engineSnapshot();
    final avgLat = SyncSchedulerMetrics.instance.avgCriticalLatencyMs ?? 0;
    String color = 'verde';
    if (!firebaseReady || levels.l1 > 20 || failsTotal > acksTotal) {
      color = 'rojo';
    } else if (levels.l1 > 0 || avgLat > 1500 || levels.l2 > 15) {
      color = 'amarillo';
    }

    return SyncHealthSnapshot(
      pending: counts[SyncOutboxStatus.pending] ?? 0,
      inflight: counts[SyncOutboxStatus.inflight] ?? 0,
      dead: counts[SyncOutboxStatus.dead] ?? 0,
      conflicts24h: conflicts,
      lastSyncAt: lastSyncAt,
      lastSyncDurationMs: lastSyncDurationMs,
      lastError: lastError,
      collectionStatus: Map<String, String>.from(collectionStatus),
      firebaseReady: firebaseReady,
      canWrite: canWrite,
      syncCycles: syncCycles,
      acksTotal: acksTotal,
      failsTotal: failsTotal,
      pendingByType: breakdown,
      pendingPreview: preview,
      pendingCritical: pendingCritical,
      pendingBackground: pendingBackground,
      pendingL1: levels.l1,
      pendingL2: levels.l2,
      pendingL3: levels.l3,
      pendingL4: levels.l4,
      scheduler: SyncSchedulerMetrics.instance.snapshot(),
      engine: engine,
      avgSyncMs: avgSyncMs,
      healthColor: color,
      history24h: history,
    );
  }
}
