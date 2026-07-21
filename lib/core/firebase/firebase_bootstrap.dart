import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../config/backend_config_service.dart';

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _initialized = false;

  static bool get isReady => _initialized;

  static Future<void> initializeIfNeeded() async {
    await BackendConfigService.instance.cargar();
    if (!DefaultFirebaseOptions.isConfigured) {
      if (BackendConfigService.instance.firebaseEnabled) {
        debugPrint(
          'Firebase habilitado pero faltan credenciales. '
          'Ejecutá: dart run tool/setup_firebase.dart',
        );
      }
      return;
    }

    if (!BackendConfigService.instance.firebaseEnabled) {
      await BackendConfigService.instance.setFirebaseEnabled(true);
    }

    if (_initialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      debugPrint('Firebase inicializado correctamente.');
    } catch (e) {
      // Si ya estaba inicializado en un hot restart / segundo intento.
      try {
        if (Firebase.apps.isNotEmpty) {
          _initialized = true;
          debugPrint('Firebase ya estaba inicializado.');
          return;
        }
      } catch (_) {}
      debugPrint('Firebase.initializeApp falló: $e');
      rethrow;
    }
  }
}
