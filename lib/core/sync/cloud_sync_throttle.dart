import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/platform_capabilities.dart';
import 'windows_sync_policy.dart';

/// Serializa trabajo de nube (sobre todo en Windows, donde ráfagas de
/// Firestore/Firebase pueden cerrar el .exe).
class CloudSyncThrottle {
  CloudSyncThrottle._();

  static Future<void> _cola = Future<void>.value();

  /// Encola [job] detrás de los anteriores. Nunca propaga el error al caller.
  ///
  /// [interactive]: acción de usuario (1 producto / listas). Usa delay corto
  /// en Windows para subir "al toque" sin ráfagas concurrentes.
  static Future<void> enqueue(
    Future<void> Function() job, {
    String tag = 'cloud',
    bool interactive = false,
  }) {
    final done = Completer<void>();
    _cola = _cola.then((_) async {
      try {
        if (PlatformCapabilities.isWindowsDesktop) {
          await Future<void>.delayed(
            interactive
                ? WindowsSyncPolicy.throttleDelayInteractive
                : WindowsSyncPolicy.throttleDelayNormal,
          );
        }
        await job();
      } catch (e, st) {
        debugPrint('CloudSyncThrottle[$tag]: $e\n$st');
      } finally {
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }
}
