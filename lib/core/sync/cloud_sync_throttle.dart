import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/platform_capabilities.dart';

/// Serializa trabajo de nube (sobre todo en Windows, donde ráfagas de
/// Firestore/Firebase pueden cerrar el .exe).
class CloudSyncThrottle {
  CloudSyncThrottle._();

  static Future<void> _cola = Future<void>.value();

  /// Encola [job] detrás de los anteriores. Nunca propaga el error al caller.
  static Future<void> enqueue(
    Future<void> Function() job, {
    String tag = 'cloud',
  }) {
    final done = Completer<void>();
    _cola = _cola.then((_) async {
      try {
        if (PlatformCapabilities.isWindowsDesktop) {
          // Respiro entre escrituras nativas.
          await Future<void>.delayed(const Duration(milliseconds: 350));
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
