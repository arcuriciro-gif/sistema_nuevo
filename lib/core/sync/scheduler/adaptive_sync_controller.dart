/// Controlador adaptativo: ajusta batch size según latencia/errores.
///
/// No usa valores fijos eternos — reacciona a la telemetría del motor.
class AdaptiveSyncController {
  AdaptiveSyncController._();
  static final AdaptiveSyncController instance = AdaptiveSyncController._();

  static const _minL1 = 4;
  static const _maxL1 = 40;
  static const _minBg = 4;
  static const _maxBg = 60;

  int batchL1 = 10;
  int batchBackground = 20;
  int workerSlotsCritical = 1;
  int workerSlotsBackground = 1;

  double emaLatencyMs = 0;
  int consecutiveErrors = 0;
  int consecutiveFast = 0;
  DateTime? lastAdaptAt;

  /// Registra latencia de una op (ms) y opcionalmente error.
  void recordSample({required int latencyMs, bool error = false}) {
    if (emaLatencyMs <= 0) {
      emaLatencyMs = latencyMs.toDouble();
    } else {
      emaLatencyMs = emaLatencyMs * 0.7 + latencyMs * 0.3;
    }
    if (error) {
      consecutiveErrors++;
      consecutiveFast = 0;
    } else {
      consecutiveErrors = 0;
      if (latencyMs < 400) {
        consecutiveFast++;
      } else {
        consecutiveFast = 0;
      }
    }
    _adapt();
  }

  void _adapt() {
    lastAdaptAt = DateTime.now().toUtc();
    // Alta latencia o errores → encoger.
    if (emaLatencyMs > 2500 || consecutiveErrors >= 2) {
      batchL1 = (batchL1 * 0.7).round().clamp(_minL1, _maxL1);
      batchBackground = (batchBackground * 0.6).round().clamp(_minBg, _maxBg);
      workerSlotsBackground = 1;
      return;
    }
    if (emaLatencyMs > 1200) {
      batchL1 = (batchL1 - 2).clamp(_minL1, _maxL1);
      batchBackground = (batchBackground - 4).clamp(_minBg, _maxBg);
      return;
    }
    // Red sana → crecer (turbo-friendly).
    if (emaLatencyMs < 350 && consecutiveFast >= 5) {
      batchL1 = (batchL1 + 2).clamp(_minL1, _maxL1);
      batchBackground = (batchBackground + 4).clamp(_minBg, _maxBg);
      workerSlotsBackground = batchBackground >= 30 ? 2 : 1;
    }
  }

  Map<String, dynamic> snapshot() => {
        'batchL1': batchL1,
        'batchBackground': batchBackground,
        'workerSlotsCritical': workerSlotsCritical,
        'workerSlotsBackground': workerSlotsBackground,
        'emaLatencyMs': emaLatencyMs,
        'consecutiveErrors': consecutiveErrors,
        'lastAdaptAt': lastAdaptAt?.toIso8601String(),
      };

  void resetForTests() {
    batchL1 = 10;
    batchBackground = 20;
    workerSlotsCritical = 1;
    workerSlotsBackground = 1;
    emaLatencyMs = 0;
    consecutiveErrors = 0;
    consecutiveFast = 0;
    lastAdaptAt = null;
  }
}
