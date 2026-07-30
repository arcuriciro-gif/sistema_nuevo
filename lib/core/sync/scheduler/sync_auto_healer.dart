import '../sync_outbox.dart';

/// Auto-healing: recupera inflight huérfanos / orphans / dead stock.
class SyncAutoHealer {
  SyncAutoHealer._();
  static final SyncAutoHealer instance = SyncAutoHealer._();

  int healsRun = 0;
  int inflightReclaimed = 0;
  int orphansAcked = 0;
  int deadStockRequeued = 0;
  DateTime? lastHealAt;
  String? lastHealDetail;

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

    final poison = await SyncOutbox.instance.forceRequeuePoisonStockOps(
      limit: 20,
    );
    deadStockRequeued += poison;
    out['poisonForceRequeued'] = poison;

    lastHealDetail = reclaimed + orphans + dead + poison > 0
        ? 'reclaimed=$reclaimed orphans=$orphans deadStock=$dead poison=$poison'
        : 'noop';
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
