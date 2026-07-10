import 'package:flutter/foundation.dart';

/// En Windows desactivamos Firebase por defecto: el Auth/Firestore nativo
/// estaba cerrando el proceso al iniciar sesión en PCs sin el entorno de
/// desarrollo. La app funciona 100% local; la sync se puede reactivar luego.
class PlatformCapabilities {
  PlatformCapabilities._();

  static bool get isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Si es false, no se inicializa ni se llama a Firebase.
  static bool get firebasePermitido => !isWindowsDesktop;
}
