// Configurado para el proyecto Firebase del usuario: tata-stock-8631e
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static bool get isConfigured => true;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return windows;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return windows;
      case TargetPlatform.macOS:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no estan configuradas para esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDIO601iRMJgk_pCERXJj3aalP5sUMRNgE',
    appId: '1:932698618413:android:79f6dd8275b301f21896a4',
    messagingSenderId: '932698618413',
    projectId: 'tata-stock-8631e',
    storageBucket: 'tata-stock-8631e.firebasestorage.app',
  );

  // TODO: reemplazar con el firebaseConfig de la app Web de tata-stock-8631e.
  // Mientras tanto Windows usa los datos del proyecto; el appId web es obligatorio.
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDIO601iRMJgk_pCERXJj3aalP5sUMRNgE',
    appId: '1:932698618413:android:79f6dd8275b301f21896a4',
    messagingSenderId: '932698618413',
    projectId: 'tata-stock-8631e',
    authDomain: 'tata-stock-8631e.firebaseapp.com',
    storageBucket: 'tata-stock-8631e.firebasestorage.app',
  );
}
