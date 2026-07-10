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

  Future<UserCredential> iniciarSesion(
    String usuario,
    String password, {
    String? email,
  }) {
    final authEmail = UsuarioAuthEmail.paraUsuario(usuario, emailReal: email);
    return _auth.signInWithEmailAndPassword(
      email: authEmail,
      password: password,
    );
  }

  /// Intenta login con email real o sintético (útil en otra PC / pendrive).
  Future<UserCredential> iniciarSesionFlexible(
    String usuarioOEmail,
    String password, {
    String? emailHint,
  }) async {
    final candidatos = <String>{};
    final entrada = usuarioOEmail.trim();
    if (UsuarioAuthEmail.esEmailReal(entrada)) {
      candidatos.add(entrada.toLowerCase());
    }
    if (emailHint != null && UsuarioAuthEmail.esEmailReal(emailHint)) {
      candidatos.add(emailHint.trim().toLowerCase());
    }
    candidatos.add(
      UsuarioAuthEmail.paraUsuario(entrada, emailReal: emailHint),
    );

    Object? ultimoError;
    for (final authEmail in candidatos) {
      try {
        return await _auth.signInWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      } catch (e) {
        ultimoError = e;
        debugPrint('Firebase login candidato $authEmail: $e');
      }
    }
    throw ultimoError ?? StateError('No se pudo iniciar sesión en Firebase.');
  }

  Future<void> cerrarSesion() => _auth.signOut();

  /// Crea la cuenta en Auth.
  /// [iniciarSesionDespues]: true en el primer login propio; false al dar de alta
  /// otro usuario (no debe pisar la sesión Firebase del administrador).
  Future<String> crearCuenta(
    String usuario,
    String password, {
    String? email,
    bool iniciarSesionDespues = true,
  }) async {
    final authEmail = UsuarioAuthEmail.paraUsuario(usuario, emailReal: email);
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
      if (iniciarSesionDespues) {
        await _auth.signInWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      }
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
