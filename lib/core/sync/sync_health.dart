import 'sync_outbox.dart';
import 'sync_watermark_store.dart';

/// Snapshot de salud de sincronización (Capacidad 2).
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

  bool get isCertifiableHealthy =>
      dead == 0 && pending < 500 && (lastError == null || pending == 0);

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
        'isCertifiableHealthy': isCertifiableHealthy,
      };
}

/// Métricas y health check de sync.
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
    final conflicts = await SyncWatermarkStore.instance.conflictsSince(
      DateTime.now().toUtc().subtract(const Duration(hours: 24)),
    );
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
    );
  }
}
