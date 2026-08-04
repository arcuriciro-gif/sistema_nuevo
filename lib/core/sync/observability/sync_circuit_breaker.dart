import 'sync_flight_recorder.dart';

/// Estados del circuit breaker de Firestore.
enum CircuitState { closed, open, halfOpen }

/// Protege contra tormentas de reintentos cuando Firebase está lento/caído.
class SyncCircuitBreaker {
  SyncCircuitBreaker._();
  static final SyncCircuitBreaker instance = SyncCircuitBreaker._();

  CircuitState state = CircuitState.closed;
  int failureStreak = 0;
  int successStreak = 0;
  int tripCount = 0;
  DateTime? openedAt;
  DateTime? lastProbeAt;
  int extraWaitMs = 0;
  double emaLatencyMs = 0;

  static const openAfterFailures = 5;
  static const openLatencyMs = 4000;
  static const coolDown = Duration(seconds: 20);
  static const halfOpenSuccessesToClose = 3;

  bool allowRequest() {
    switch (state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        final opened = openedAt;
        if (opened == null) return true;
        if (DateTime.now().toUtc().difference(opened) >= coolDown) {
          state = CircuitState.halfOpen;
          lastProbeAt = DateTime.now().toUtc();
          SyncFlightRecorder.instance.record(
            kind: 'circuit',
            message: 'half_open_probe',
          );
          return true;
        }
        return false;
      case CircuitState.halfOpen:
        final last = lastProbeAt;
        if (last != null &&
            DateTime.now().toUtc().difference(last) <
                const Duration(seconds: 2)) {
          return false;
        }
        lastProbeAt = DateTime.now().toUtc();
        return true;
    }
  }

  void recordSuccess({required int latencyMs}) {
    _updateEma(latencyMs);
    failureStreak = 0;
    if (state == CircuitState.halfOpen) {
      successStreak++;
      if (successStreak >= halfOpenSuccessesToClose) {
        state = CircuitState.closed;
        successStreak = 0;
        openedAt = null;
        extraWaitMs = 0;
        SyncFlightRecorder.instance.record(
          kind: 'circuit',
          message: 'closed_recovered',
        );
      }
    } else if (latencyMs >= openLatencyMs) {
      failureStreak++;
      _maybeOpen(reason: 'slow_${latencyMs}ms');
    }
  }

  void recordFailure({required int latencyMs}) {
    _updateEma(latencyMs);
    failureStreak++;
    successStreak = 0;
    _maybeOpen(reason: 'error_${latencyMs}ms');
  }

  void _updateEma(int latencyMs) {
    if (emaLatencyMs <= 0) {
      emaLatencyMs = latencyMs.toDouble();
    } else {
      emaLatencyMs = emaLatencyMs * 0.7 + latencyMs * 0.3;
    }
  }

  void _maybeOpen({required String reason}) {
    if (state == CircuitState.open) return;
    if (failureStreak >= openAfterFailures || emaLatencyMs > openLatencyMs) {
      state = CircuitState.open;
      openedAt = DateTime.now().toUtc();
      tripCount++;
      extraWaitMs = (extraWaitMs + 250).clamp(0, 2000);
      SyncFlightRecorder.instance.record(
        kind: 'circuit',
        message: 'opened',
        data: {
          'reason': reason,
          'failures': failureStreak,
          'extraWaitMs': extraWaitMs,
          'tripCount': tripCount,
        },
      );
    }
  }

  Map<String, dynamic> snapshot() => {
        'state': state.name,
        'failureStreak': failureStreak,
        'successStreak': successStreak,
        'tripCount': tripCount,
        'extraWaitMs': extraWaitMs,
        'emaLatencyMs': emaLatencyMs,
        'openedAt': openedAt?.toIso8601String(),
        'coolDownSec': coolDown.inSeconds,
      };

  void resetForTests() {
    state = CircuitState.closed;
    failureStreak = 0;
    successStreak = 0;
    tripCount = 0;
    openedAt = null;
    lastProbeAt = null;
    extraWaitMs = 0;
    emaLatencyMs = 0;
  }
}
