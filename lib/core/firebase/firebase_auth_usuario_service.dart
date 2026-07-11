import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../auth/usuario_auth_email.dart';
import '../config/backend_config_service.dart';
import 'firebase_bootstrap.dart';

class FirebaseAuthUsuarioService {
  FirebaseAuthUsuarioService._();

  static final FirebaseAuthUsuarioService instance =
      FirebaseAuthUsuarioService._();

  bool get disponible =>
      BackendConfigService.instance.firebaseEnabled && FirebaseBootstrap.isReady;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Email que se usa en Firebase Auth para este usuario.
  String emailPara(String usuario, {String? email}) =>
      UsuarioAuthEmail.paraUsuario(usuario, emailReal: email);

  /// Mensaje legible de errores de Firebase Auth.
  static String mensajeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'operation-not-allowed':
          return 'En Firebase Console activá Authentication → Correo/contraseña.';
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'La contraseña no coincide con la de la nube. '
              'Usá la misma clave en PC y celular.';
        case 'user-not-found':
          return 'No existe esa cuenta en Firebase Auth.';
        case 'email-already-in-use':
          return 'La cuenta ya existe en la nube. Usá la contraseña definida en el otro dispositivo.';
        case 'weak-password':
          return 'La contraseña debe tener al menos 6 caracteres.';
        case 'invalid-email':
          return 'Email de Auth inválido: ${error.message ?? error.code}';
        case 'network-request-failed':
          return 'Sin internet para conectar con Firebase.';
        case 'too-many-requests':
          return 'Demasiados intentos. Esperá un momento y reintentá.';
        default:
          return 'Firebase Auth (${error.code}): ${error.message ?? error}';
      }
    }
    return error.toString();
  }

  Future<UserCredential> iniciarSesion(
    String usuario,
    String password, {
    String? email,
  }) {
    final authEmail = emailPara(usuario, email: email);
    debugPrint('Firebase signIn email=$authEmail');
    return _auth.signInWithEmailAndPassword(
      email: authEmail,
      password: password,
    );
  }

  Future<void> cerrarSesion() => _auth.signOut();

  Future<String> crearCuenta(
    String usuario,
    String password, {
    String? email,
  }) async {
    final authEmail = UsuarioAuthEmail.paraUsuario(usuario, emailReal: email);

    // Si no hay sesión en la app principal, crear directo (más fiable en Windows).
    if (_auth.currentUser == null) {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      return cred.user!.uid;
    }

    // Hay un usuario logueado (ej. admin creando otro): usar app secundaria
    // para no cerrar la sesión actual.
    final appName = 'UsuarioCreator_${DateTime.now().millisecondsSinceEpoch}';
    final secondary = await Firebase.initializeApp(
      name: appName,
      options: _auth.app.options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final uid = cred.user!.uid;
      await secondaryAuth.signOut();
      return uid;
    } finally {
      await secondary.delete();
    }
  }

  Future<void> cambiarPasswordActual(String passwordNueva) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa de Firebase.');
    }
    await user.updatePassword(passwordNueva);
  }

  Future<void> actualizarEmailActual(String emailNuevo) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No hay sesión activa de Firebase.');
    }
    await user.verifyBeforeUpdateEmail(emailNuevo.trim().toLowerCase());
  }

  Future<void> enviarVerificacionEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } catch (e) {
      debugPrint('enviarVerificacionEmail: $e');
      rethrow;
    }
  }

  Future<void> enviarRestablecimiento(String usuario, {String? email}) async {
    final authEmail = UsuarioAuthEmail.paraUsuario(usuario, emailReal: email);
    await _auth.sendPasswordResetEmail(email: authEmail);
  }

  Future<void> enviarConfirmacionAlta({
    required String usuario,
    required String email,
  }) async {
    if (!UsuarioAuthEmail.esEmailReal(email)) {
      throw StateError('Se necesita un email real para enviar la confirmación.');
    }
    // Aviso al nuevo usuario: puede definir/recuperar su contraseña.
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    // Si hay sesión del usuario recién creado, también verificación.
    final user = _auth.currentUser;
    if (user != null &&
        (user.email ?? '').toLowerCase() == email.trim().toLowerCase() &&
        !user.emailVerified) {
      try {
        await user.sendEmailVerification();
      } catch (e) {
        debugPrint('sendEmailVerification: $e');
      }
    }
  }

  String? get uidActual => _auth.currentUser?.uid;
}
