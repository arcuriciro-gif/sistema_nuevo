import '../sync_outbox.dart';
import 'sync_auto_healer.dart';
import 'sync_priority.dart';
import 'sync_scheduler_metrics.dart';

/// Scheduler mínimo: claim por prioridad + auto-heal.
/// Sin Turbo / Adaptive / locks / state store.
class SyncScheduler {
  SyncScheduler._();
  static final SyncScheduler instance = SyncScheduler._();

  final metrics = SyncSchedulerMetrics.instance;
  final healer = SyncAutoHealer.instance;

  String lastMode = 'idle';

  Future<void> ensureRestored() async {
    // Compat API: no hay estado turbo/adaptive que restaurar.
  }

  static ({int l1, int l2, int l3, int l4}) countLevels(
    Map<String, int> breakdown,
  ) {
    var l1 = 0, l2 = 0, l3 = 0, l4 = 0;
    for (final e in breakdown.entries) {
      switch (SyncPriority.levelForEntityType(e.key)) {
        case SyncPriorityLevel.critical:
          l1 += e.value;
        case SyncPriorityLevel.high:
          l2 += e.value;
        case SyncPriorityLevel.normal:
          l3 += e.value;
        case SyncPriorityLevel.background:
          l4 += e.value;
      }
    }
    return (l1: l1, l2: l2, l3: l3, l4: l4);
  }

  /// Claim fijo: venta/stock/remito antes que productos.
  Future<List<Map<String, dynamic>>> claimForTick({
    required Map<String, int> breakdown,
    required bool isWindows,
  }) async {
    final _ = breakdown;
    lastMode = 'fixed';
    final claimed = await SyncOutbox.instance.claimBatch(
      limit: isWindows ? 8 : 20,
      orderByPriority: true,
    );
    metrics.recordTick(critical: claimed.any((o) {
      final t = o['entity_type']?.toString() ?? '';
      return SyncPriority.isCriticalEntity(t);
    }));
    return claimed;
  }

  Future<bool> shouldPreempt() async {
    final bd = await SyncOutbox.instance.pendingBreakdown();
    final counts = countLevels(bd);
    return counts.l1 > 0;
  }

  Future<void> recordOpResult({
    required String entityType,
    required int latencyMs,
    required bool error,
    required bool firestoreOk,
  }) async {
    final critical = SyncPriority.isCriticalEntity(entityType);
    if (error) {
      metrics.recordFail(critical: critical);
    } else {
      metrics.recordSuccess(critical: critical, latencyMs: latencyMs);
    }
  }

  Future<Map<String, int>> runAutoHeal({
    Duration staleInflight = const Duration(minutes: 3),
  }) =>
      healer.heal(staleInflight: staleInflight);

  Map<String, dynamic> engineSnapshot() => {
        'mode': lastMode,
        'healer': healer.snapshot(),
        'metrics': metrics.snapshot(),
      };
}
