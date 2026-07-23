import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ejecuta sync sin bloquear la UI y sin romper tests si la DB ya cerró.
void syncInBackground(Future<void> future, {String tag = 'sync'}) {
  unawaited(
    future.then(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('$tag (bg): $e');
      },
    ),
  );
}
