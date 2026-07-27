import 'adaptive_sync_controller.dart';
import 'sync_scheduler_policy.dart';

/// Modo Turbo: cuando L1+L2 vacíos, el motor usa toda la capacidad en fondo.
/// Al aparecer una venta/stock, preempta y libera recursos al instante.
class TurboModeController {
  TurboModeController._();
  static final TurboModeController instance = TurboModeController._();

  bool active = false;
  int turboTicks = 0;
  int preemptionCount = 0;
  DateTime? lastTurboAt;
  DateTime? lastPreemptAt;

  SyncLevelClaims evaluate({
    required int pendingL1,
    required int pendingL2,
    required int pendingL3,
    required int pendingL4,
    required bool isWindows,
  }) {
    final adaptive = AdaptiveSyncController.instance;
    final plan = SyncSchedulerPolicy.planLevels(
      pendingL1: pendingL1,
      pendingL2: pendingL2,
      pendingL3: pendingL3,
      pendingL4: pendingL4,
      isWindows: isWindows,
      adaptiveBatchL1: adaptive.batchL1,
      adaptiveBatchBg: adaptive.batchBackground,
    );

    if (plan.turboActive) {
      active = true;
      turboTicks++;
      lastTurboAt = DateTime.now().toUtc();
    } else if (active && pendingL1 > 0) {
      // Salía de turbo por preemption L1.
      preemptionCount++;
      lastPreemptAt = DateTime.now().toUtc();
      active = false;
    } else if (!plan.turboActive) {
      active = false;
    }
    return plan;
  }

  Map<String, dynamic> snapshot() => {
        'turboActive': active,
        'turboTicks': turboTicks,
        'preemptionCount': preemptionCount,
        'lastTurboAt': lastTurboAt?.toIso8601String(),
        'lastPreemptAt': lastPreemptAt?.toIso8601String(),
      };

  void resetForTests() {
    active = false;
    turboTicks = 0;
    preemptionCount = 0;
    lastTurboAt = null;
    lastPreemptAt = null;
  }
}
