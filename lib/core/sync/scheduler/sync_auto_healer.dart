import '../sync_outbox.dart';
import 'scheduler_state_store.dart';

/// Auto-healing del Sync Engine: recupera colas congeladas sin intervención.
class SyncAutoHealer {
  SyncAutoHealer._();
  static final SyncAutoHealer instance = SyncAutoHealer._();

  int healsRun = 0;
  int inflightReclaimed = 0;
  int orphansAcked = 0;
  int deadStockRequeued = 0;
  DateTime? lastHealAt;
  String? lastHealDetail;

  /// Ejecuta un ciclo de recuperación (idempotente, seguro).
  Future<Map<String, int>> heal({
    Duration staleInflight = const Duration(minutes: 3),
  }) async {
    healsRun++;
    lastHealAt = DateTime.now().toUtc();
    final out = <String, int>{};

    final reclaimed = await SyncOutbox.instance.reclaimStaleInflight(
      olderThan: staleInflight,
    );
    inflightReclaimed += reclaimed;
    out['inflightReclaimed'] = reclaimed;

    final orphans = await SyncOutbox.instance.ackOrphanUpserts();
    orphansAcked += orphans;
    out['orphansAcked'] = orphans;

    final dead = await SyncOutbox.instance.ackDeadStockOps();
    deadStockRequeued += dead;
    out['deadStockRequeued'] = dead;

    // Persistir modo recovering si hubo trabajo.
    if (reclaimed + orphans + dead > 0) {
      lastHealDetail =
          'reclaimed=$reclaimed orphans=$orphans deadStock=$dead';
      try {
        await SchedulerStateStore.instance.save(
          mode: 'recovering',
          turboActive: false,
          adaptiveBatchL1: 8,
          adaptiveBatchBg: 12,
          lastFirestoreLatencyMs: 0,
          checkpoint: {'heal': lastHealDetail, 'at': lastHealAt!.toIso8601String()},
        );
      } catch (_) {}
    } else {
      lastHealDetail = 'noop';
    }
    return out;
  }

  Map<String, dynamic> snapshot() => {
        'healsRun': healsRun,
        'inflightReclaimed': inflightReclaimed,
        'orphansAcked': orphansAcked,
        'deadStockRequeued': deadStockRequeued,
        'lastHealAt': lastHealAt?.toIso8601String(),
        'lastHealDetail': lastHealDetail,
      };

  void resetForTests() {
    healsRun = 0;
    inflightReclaimed = 0;
    orphansAcked = 0;
    deadStockRequeued = 0;
    lastHealAt = null;
    lastHealDetail = null;
  }
}
