import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/platform_capabilities.dart';
import 'windows_sync_policy.dart';
import 'scheduler/sync_priority.dart';

/// Throttle multi-carril: L1 nunca espera detrás de import/masivos.
class CloudSyncThrottle {
  CloudSyncThrottle._();

  static Future<void> _colaCritica = Future<void>.value();
  static Future<void> _colaFondo = Future<void>.value();

  /// @Deprecated — usar [enqueueCritical] / [enqueueBackground].
  static Future<void> enqueue(
    Future<void> Function() job, {
    String tag = 'cloud',
    bool interactive = false,
  }) {
    if (interactive) {
      return enqueueCritical(job, tag: tag);
    }
    return enqueueBackground(job, tag: tag);
  }

  static Future<void> enqueueCritical(
    Future<void> Function() job, {
    String tag = 'critical',
  }) {
    return _enqueue(lane: SyncLane.critical, job: job, tag: tag);
  }

  static Future<void> enqueueHigh(
    Future<void> Function() job, {
    String tag = 'high',
  }) {
    // L2 comparte carril crítico (no espera detrás de import).
    return _enqueue(lane: SyncLane.critical, job: job, tag: tag);
  }

  static Future<void> enqueueBackground(
    Future<void> Function() job, {
    String tag = 'background',
  }) {
    return _enqueue(lane: SyncLane.background, job: job, tag: tag);
  }

  static Future<void> _enqueue({
    required SyncLane lane,
    required Future<void> Function() job,
    required String tag,
  }) {
    final isCrit =
        lane == SyncLane.critical || lane == SyncLane.high;
    final done = Completer<void>();
    final chain = isCrit ? _colaCritica : _colaFondo;
    final next = chain.then((_) async {
      try {
        if (PlatformCapabilities.isWindowsDesktop) {
          await Future<void>.delayed(
            isCrit
                ? WindowsSyncPolicy.throttleDelayInteractive
                : WindowsSyncPolicy.throttleDelayNormal,
          );
        }
        await job();
      } catch (e, st) {
        debugPrint('CloudSyncThrottle[$tag/$lane]: $e\n$st');
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
    if (isCrit) {
      _colaCritica = next;
    } else {
      _colaFondo = next;
    }
    return done.future;
  }

  static void resetForTests() {
    _colaCritica = Future<void>.value();
    _colaFondo = Future<void>.value();
  }
}
