import '../sync_outbox.dart';
import 'adaptive_sync_controller.dart';
import 'entity_lock_registry.dart';
import 'scheduler_state_store.dart';
import 'sync_auto_healer.dart';
import 'sync_metrics_history_store.dart';
import 'sync_priority.dart';
import 'sync_scheduler_metrics.dart';
import 'sync_scheduler_policy.dart';
import 'turbo_mode_controller.dart';
import 'package:flutter/foundation.dart';

/// Sync Engine 2.0 — scheduler inteligente con Turbo, preemption y adaptación.
///
/// No ejecuta Firebase aquí: planifica claims. El pump de FirestoreSyncService
/// ejecuta, mide latencia y llama [shouldPreempt] entre ops de fondo.
class SyncScheduler {
  SyncScheduler._();
  static final SyncScheduler instance = SyncScheduler._();

  final metrics = SyncSchedulerMetrics.instance;
  final turbo = TurboModeController.instance;
  final adaptive = AdaptiveSyncController.instance;
  final locks = EntityLockRegistry.instance;
  final healer = SyncAutoHealer.instance;

  String lastMode = 'idle';
  bool _restored = false;
  DateTime? _lastHistorySampleAt;

  /// Restaura adaptive/turbo desde SQLite (una vez por proceso).
  Future<void> ensureRestored() async {
    if (_restored) return;
    _restored = true;
    try {
      final s = await SchedulerStateStore.instance.load();
      if (s == null) return;
      adaptive.batchL1 = s.adaptiveBatchL1;
      adaptive.batchBackground = s.adaptiveBatchBg;
      adaptive.emaLatencyMs = s.lastFirestoreLatencyMs;
      lastMode = s.mode;
      turbo.active = s.turboActive;
    } catch (_) {}
  }

  /// Cuenta pendientes por nivel a partir del breakdown de entity_type.
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

  SyncSchedulerPlan planFromBreakdown(
    Map<String, int> breakdown, {
    required bool isWindows,
  }) {
    final counts = countLevels(breakdown);
    final levels = turbo.evaluate(
      pendingL1: counts.l1,
      pendingL2: counts.l2,
      pendingL3: counts.l3,
      pendingL4: counts.l4,
      isWindows: isWindows,
    );
    lastMode = levels.mode;
    metrics.recordTick(critical: levels.l1 + levels.l2 > 0);
    if (levels.l3 + levels.l4 > 0) {
      metrics.recordTick(critical: false);
    }
    metrics.recordTurbo(levels.turboActive);
    return SyncSchedulerPlan(
      criticalClaim: levels.l1 + levels.l2,
      backgroundClaim: levels.l3 + levels.l4,
      criticalTypes: SyncSchedulerPolicy.criticalEntityTypes,
      backgroundTypes: SyncSchedulerPolicy.backgroundEntityTypes,
      turboActive: levels.turboActive,
      levelClaims: levels,
    );
  }

  /// Claim por niveles según Turbo / focused.
  Future<List<Map<String, dynamic>>> claimForTick({
    required Map<String, int> breakdown,
    required bool isWindows,
  }) async {
    await ensureRestored();
    final plan = planFromBreakdown(breakdown, isWindows: isWindows);
    final levels = plan.levelClaims;
    final claimed = <Map<String, dynamic>>[];

    Future<void> claim(List<String> types, int limit) async {
      if (limit <= 0 || types.isEmpty) return;
      final batch = await SyncOutbox.instance.claimBatch(
        limit: limit,
        entityTypes: types,
        orderByPriority: true,
      );
      claimed.addAll(batch);
    }

    if (levels != null) {
      await claim(SyncSchedulerPolicy.level1Types, levels.l1);
      await claim(SyncSchedulerPolicy.level2Types, levels.l2);
      await claim(SyncSchedulerPolicy.level3Types, levels.l3);
      await claim(SyncSchedulerPolicy.level4Types, levels.l4);
    } else {
      if (plan.criticalClaim > 0) {
        await claim(plan.criticalTypes, plan.criticalClaim);
      }
      if (plan.backgroundClaim > 0) {
        await claim(plan.backgroundTypes, plan.backgroundClaim);
      }
    }

    // Persistencia del checkpoint del tick.
    try {
      await SchedulerStateStore.instance.save(
        mode: lastMode,
        turboActive: plan.turboActive,
        adaptiveBatchL1: adaptive.batchL1,
        adaptiveBatchBg: adaptive.batchBackground,
        lastFirestoreLatencyMs: adaptive.emaLatencyMs,
        checkpoint: {
          'claimed': claimed.length,
          'turbo': plan.turboActive,
          'l1': levels?.l1,
          'l2': levels?.l2,
          'l3': levels?.l3,
          'l4': levels?.l4,
        },
      );
    } catch (_) {}

    return claimed;
  }

  /// ¿Hay que abortar el lote de fondo? (venta/stock llegó).
  Future<bool> shouldPreempt() async {
    final bd = await SyncOutbox.instance.pendingBreakdown();
    final counts = countLevels(bd);
    if (SyncSchedulerPolicy.shouldPreemptBackground(pendingL1: counts.l1)) {
      turbo.preemptionCount++;
      turbo.lastPreemptAt = DateTime.now().toUtc();
      turbo.active = false;
      metrics.recordPreempt();
      return true;
    }
    return false;
  }

  Future<void> recordOpResult({
    required String entityType,
    required int latencyMs,
    required bool error,
    required bool firestoreOk,
  }) async {
    final critical = SyncPriority.isCriticalEntity(entityType);
    adaptive.recordSample(latencyMs: latencyMs, error: error);
    if (error) {
      metrics.recordFail(critical: critical);
    } else {
      metrics.recordSuccess(critical: critical, latencyMs: latencyMs);
    }
    // Sample historial ~1/min.
    final now = DateTime.now().toUtc();
    if (_lastHistorySampleAt == null ||
        now.difference(_lastHistorySampleAt!) > const Duration(minutes: 1)) {
      _lastHistorySampleAt = now;
      try {
        final bd = await SyncOutbox.instance.pendingBreakdown();
        final c = countLevels(bd);
        await SyncMetricsHistoryStore.instance.record(
          SyncMetricsSample(
            at: now.toIso8601String(),
            pendingL1: c.l1,
            pendingL2: c.l2,
            pendingL3: c.l3,
            pendingL4: c.l4,
            opsPerMin: metrics.opsPerMinuteCritical() ?? 0,
            avgLatencyMs: adaptive.emaLatencyMs,
            maxLatencyMs: (metrics.maxCriticalLatencyMs ?? 0).toDouble(),
            errors: adaptive.consecutiveErrors,
            turbo: turbo.active,
            firestoreOk: firestoreOk,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> runAutoHeal() => healer.heal();

  Map<String, dynamic> engineSnapshot() => {
        'mode': lastMode,
        'turbo': turbo.snapshot(),
        'adaptive': adaptive.snapshot(),
        'metrics': metrics.snapshot(),
        'healer': healer.snapshot(),
        'locksHeld': locks.heldCount,
      };

  @visibleForTesting
  void resetForTests() {
    _restored = false;
    lastMode = 'idle';
    _lastHistorySampleAt = null;
    metrics.resetForTests();
    turbo.resetForTests();
    adaptive.resetForTests();
    healer.resetForTests();
    locks.resetForTests();
  }
}
