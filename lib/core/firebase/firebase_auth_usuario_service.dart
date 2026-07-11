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

  /// Email de Auth SIEMPRE sintético (usuario@tenant.tatastock.app).
  /// El Gmail del formulario es solo contacto; no se usa para login.
  String authEmailPara(String usuario) => UsuarioAuthEmail.sintetico(usuario);

  /// Mensaje legible de errores de Firebase Auth.
  static String mensajeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'operation-not-allowed':
          return 'En Firebase Console activá Authentication → Correo/contraseña.';
        case 'wrong-password':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'Contraseña incorrecta. '
              'Pedile al admin: Usuarios → Restablecer contraseña.';
        case 'user-not-found':
          return 'No existe esa cuenta en la nube. '
              'Pedile al admin que vuelva a crear o restablecer el usuario.';
        case 'email-already-in-use':
          return 'La cuenta ya existe en la nube con otra clave. '
              'Admin: Usuarios → Restablecer, o en Firebase Console '
              'Authentication → Users eliminá la cuenta vieja.';
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

  /// Login Auth: prueba email sintético y, si hay, el email real (cuentas viejas).
  Future<UserCredential> iniciarSesion(
    String usuario,
    String password, {
    String? email,
  }) async {
    final sintetico = authEmailPara(usuario);
    try {
      debugPrint('Firebase signIn email=$sintetico');
      return await _auth.signInWithEmailAndPassword(
        email: sintetico,
        password: password,
      );
    } catch (e) {
      final real = (email ?? '').trim();
      if (UsuarioAuthEmail.esEmailReal(real) &&
          real.toLowerCase() != sintetico.toLowerCase()) {
        debugPrint('Firebase signIn fallback email=$real');
        return _auth.signInWithEmailAndPassword(
          email: real.toLowerCase(),
          password: password,
        );
      }
      rethrow;
    }
  }

  Future<void> cerrarSesion() => _auth.signOut();

  /// Crea o reutiliza la cuenta Auth del usuario con la clave indicada.
  /// Siempre usa email sintético para que PC y Android entren igual.
  Future<String> asegurarCuenta(String usuario, String password) async {
    final authEmail = authEmailPara(usuario);
    final nombreApp =
        'UsuarioAuth_${DateTime.now().millisecondsSinceEpoch}';

    Future<String> conAuth(FirebaseAuth auth) async {
      try {
        final cred = await auth.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
        return cred.user!.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await auth.signInWithEmailAndPassword(
              email: authEmail,
              password: password,
            );
            return cred.user!.uid;
          } on FirebaseAuthException catch (e2) {
            throw StateError(
              'La cuenta de nube de "$usuario" ya existe con OTRA clave.\n\n'
              'Solución rápida:\n'
              '1) Firebase Console → Authentication → Users\n'
              '2) Eliminá: $authEmail\n'
              '3) En la app: Usuarios → Restablecer contraseña de $usuario\n\n'
              '(${mensajeError(e2)})',
            );
          }
        }
        throw StateError(mensajeError(e));
      }
    }

    // Sin sesión: crear en la app principal.
    if (_auth.currentUser == null) {
      return conAuth(_auth);
    }

    // Admin logueado: app secundaria para no cerrar su sesión.
    final secondary = await Firebase.initializeApp(
      name: nombreApp,
      options: _auth.app.options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final uid = await conAuth(secondaryAuth);
      try {
        await secondaryAuth.signOut();
      } catch (_) {}
      return uid;
    } finally {
      try {
        await secondary.delete();
      } catch (_) {}
    }
  }

  Future<String> crearCuenta(
    String usuario,
    String password, {
    String? email,
  }) =>
      asegurarCuenta(usuario, password);

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
    // Preferir email real si existe (puede recibir el mail); si no, sintético.
    final authEmail = UsuarioAuthEmail.esEmailReal(email)
        ? email!.trim().toLowerCase()
        : authEmailPara(usuario);
    await _auth.sendPasswordResetEmail(email: authEmail);
  }

  Future<void> enviarConfirmacionAlta({
    required String usuario,
    required String email,
  }) async {
    debugPrint(
      'Alta usuario=$usuario: Auth=${authEmailPara(usuario)} contacto=$email',
    );
  }

  String? get uidActual => _auth.currentUser?.uid;
}
