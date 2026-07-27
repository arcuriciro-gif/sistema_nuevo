/// Métricas del scheduler (antes/después observables).
class SyncSchedulerMetrics {
  SyncSchedulerMetrics._();
  static final SyncSchedulerMetrics instance = SyncSchedulerMetrics._();

  int criticalProcessed = 0;
  int backgroundProcessed = 0;
  int criticalFails = 0;
  int backgroundFails = 0;
  int coalescedOps = 0;
  int criticalTicks = 0;
  int backgroundTicks = 0;

  final List<int> _criticalLatenciesMs = [];
  final List<int> _backgroundLatenciesMs = [];

  DateTime? lastCriticalAt;
  DateTime? lastBackgroundAt;
  DateTime? lastTickAt;

  void recordSuccess({
    required bool critical,
    required int latencyMs,
  }) {
    if (critical) {
      criticalProcessed++;
      lastCriticalAt = DateTime.now().toUtc();
      _criticalLatenciesMs.add(latencyMs);
      if (_criticalLatenciesMs.length > 200) {
        _criticalLatenciesMs.removeAt(0);
      }
    } else {
      backgroundProcessed++;
      lastBackgroundAt = DateTime.now().toUtc();
      _backgroundLatenciesMs.add(latencyMs);
      if (_backgroundLatenciesMs.length > 200) {
        _backgroundLatenciesMs.removeAt(0);
      }
    }
  }

  void recordFail({required bool critical}) {
    if (critical) {
      criticalFails++;
    } else {
      backgroundFails++;
    }
  }

  void recordCoalesce() => coalescedOps++;

  void recordTick({required bool critical}) {
    lastTickAt = DateTime.now().toUtc();
    if (critical) {
      criticalTicks++;
    } else {
      backgroundTicks++;
    }
  }

  double? get avgCriticalLatencyMs => _avg(_criticalLatenciesMs);
  double? get avgBackgroundLatencyMs => _avg(_backgroundLatenciesMs);
  int? get maxCriticalLatencyMs => _max(_criticalLatenciesMs);
  int? get maxBackgroundLatencyMs => _max(_backgroundLatenciesMs);

  double? opsPerMinuteCritical() {
    if (lastCriticalAt == null || criticalProcessed == 0) return null;
    // Aprox sobre ventana de muestras.
    final n = _criticalLatenciesMs.length;
    if (n < 2) return criticalProcessed.toDouble();
    final sumMs = _criticalLatenciesMs.fold<int>(0, (a, b) => a + b);
    if (sumMs <= 0) return null;
    return n * 60000.0 / sumMs;
  }

  Map<String, dynamic> snapshot() => {
        'criticalProcessed': criticalProcessed,
        'backgroundProcessed': backgroundProcessed,
        'criticalFails': criticalFails,
        'backgroundFails': backgroundFails,
        'coalescedOps': coalescedOps,
        'criticalTicks': criticalTicks,
        'backgroundTicks': backgroundTicks,
        'avgCriticalLatencyMs': avgCriticalLatencyMs,
        'avgBackgroundLatencyMs': avgBackgroundLatencyMs,
        'maxCriticalLatencyMs': maxCriticalLatencyMs,
        'maxBackgroundLatencyMs': maxBackgroundLatencyMs,
        'opsPerMinuteCritical': opsPerMinuteCritical(),
        'lastCriticalAt': lastCriticalAt?.toIso8601String(),
        'lastBackgroundAt': lastBackgroundAt?.toIso8601String(),
        'lastTickAt': lastTickAt?.toIso8601String(),
      };

  void resetForTests() {
    criticalProcessed = 0;
    backgroundProcessed = 0;
    criticalFails = 0;
    backgroundFails = 0;
    coalescedOps = 0;
    criticalTicks = 0;
    backgroundTicks = 0;
    _criticalLatenciesMs.clear();
    _backgroundLatenciesMs.clear();
    lastCriticalAt = null;
    lastBackgroundAt = null;
    lastTickAt = null;
  }

  static double? _avg(List<int> xs) {
    if (xs.isEmpty) return null;
    return xs.fold<int>(0, (a, b) => a + b) / xs.length;
  }

  static int? _max(List<int> xs) {
    if (xs.isEmpty) return null;
    return xs.reduce((a, b) => a > b ? a : b);
  }
}
