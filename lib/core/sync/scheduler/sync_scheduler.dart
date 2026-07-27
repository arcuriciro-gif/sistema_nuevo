import '../sync_outbox.dart';
import 'sync_priority.dart';
import 'sync_scheduler_metrics.dart';
import 'sync_scheduler_policy.dart';

/// Scheduler: dos carriles. Crítico nunca espera detrás de import/masivos.
///
/// No ejecuta Firebase aquí: solo **planifica claims** del outbox. El pump
/// de [FirestoreSyncService] ejecuta las ops y reporta métricas.
class SyncScheduler {
  SyncScheduler._();
  static final SyncScheduler instance = SyncScheduler._();

  final metrics = SyncSchedulerMetrics.instance;

  /// Arma el plan del tick a partir del breakdown de pendientes.
  SyncSchedulerPlan planFromBreakdown(
    Map<String, int> breakdown, {
    required bool isWindows,
  }) {
    var pendingCritical = 0;
    var pendingBackground = 0;
    for (final e in breakdown.entries) {
      if (SyncPriority.isCriticalEntity(e.key)) {
        pendingCritical += e.value;
      } else {
        pendingBackground += e.value;
      }
    }
    final plan = SyncSchedulerPolicy.planTick(
      pendingCritical: pendingCritical,
      pendingBackground: pendingBackground,
      isWindows: isWindows,
    );
    metrics.recordTick(critical: plan.criticalClaim > 0);
    if (plan.backgroundClaim > 0) {
      metrics.recordTick(critical: false);
    }
    return plan;
  }

  /// Claim ordenado: primero crítico, luego fondo (cupos del plan).
  Future<List<Map<String, dynamic>>> claimForTick({
    required Map<String, int> breakdown,
    required bool isWindows,
  }) async {
    final plan = planFromBreakdown(breakdown, isWindows: isWindows);
    final claimed = <Map<String, dynamic>>[];

    if (plan.criticalClaim > 0) {
      final crit = await SyncOutbox.instance.claimBatch(
        limit: plan.criticalClaim,
        entityTypes: plan.criticalTypes,
        orderByPriority: true,
      );
      claimed.addAll(crit);
    }
    if (plan.backgroundClaim > 0) {
      final bg = await SyncOutbox.instance.claimBatch(
        limit: plan.backgroundClaim,
        entityTypes: plan.backgroundTypes,
        orderByPriority: true,
      );
      claimed.addAll(bg);
    }
    return claimed;
  }
}
