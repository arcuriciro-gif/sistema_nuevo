import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/platform_capabilities.dart';
import 'windows_sync_policy.dart';
import 'scheduler/sync_priority.dart';

/// Throttle de dos carriles: crítico NUNCA espera detrás de import/masivos.
class CloudSyncThrottle {
  CloudSyncThrottle._();

  static Future<void> _colaCritica = Future<void>.value();
  static Future<void> _colaFondo = Future<void>.value();

  /// @Deprecated — usar [enqueueCritical] / [enqueueBackground].
  /// Se mantiene: jobs sin lane van a crítico si [interactive], si no a fondo.
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
    return _enqueue(
      lane: SyncLane.critical,
      job: job,
      tag: tag,
    );
  }

  static Future<void> enqueueBackground(
    Future<void> Function() job, {
    String tag = 'background',
  }) {
    return _enqueue(
      lane: SyncLane.background,
      job: job,
      tag: tag,
    );
  }

  static Future<void> _enqueue({
    required SyncLane lane,
    required Future<void> Function() job,
    required String tag,
  }) {
    final done = Completer<void>();
    final chain = lane == SyncLane.critical ? _colaCritica : _colaFondo;
    final next = chain.then((_) async {
      try {
        if (PlatformCapabilities.isWindowsDesktop) {
          await Future<void>.delayed(
            lane == SyncLane.critical
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
    if (lane == SyncLane.critical) {
      _colaCritica = next;
    } else {
      _colaFondo = next;
    }
    return done.future;
  }

  /// Tests: reinicia colas.
  static void resetForTests() {
    _colaCritica = Future<void>.value();
    _colaFondo = Future<void>.value();
  }
}
