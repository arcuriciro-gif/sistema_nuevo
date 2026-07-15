import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../firebase_options.dart';
import '../auth/usuario_auth_email.dart';
import '../config/backend_config_service.dart';
import 'firebase_bootstrap.dart';

class FirebaseAuthUsuarioService {
  FirebaseAuthUsuarioService._();

  static final FirebaseAuthUsuarioService instance =
      FirebaseAuthUsuarioService._();

  static bool get _appsListas {
    if (!FirebaseBootstrap.isReady) return false;
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get disponible =>
      BackendConfigService.instance.firebaseEnabled && _appsListas;

  FirebaseAuth? get _authOrNull {
    if (!_appsListas) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth get _auth {
    final a = _authOrNull;
    if (a == null) {
      throw StateError(
        'Firebase no está inicializado. Activá la sincronización en Configuración.',
      );
    }
    return a;
  }

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

  Future<void> cerrarSesion() async {
    try {
      final auth = _authOrNull;
      if (auth != null) await auth.signOut();
    } catch (_) {}
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }
  }

  /// Google → sesión Firebase. Devuelve el User de Firebase con email.
  Future<User> iniciarSesionConGoogle() async {
    if (!disponible) {
      throw StateError(
        'Firebase no está listo. Activá la sincronización online '
        '(Configuración) o revisá internet.',
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      return _googleSignInAndroid();
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      try {
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        final cred = await _auth.signInWithProvider(provider);
        final user = cred.user;
        if (user == null || (user.email ?? '').isEmpty) {
          throw StateError('Google no devolvió un email.');
        }
        return user;
      } catch (e) {
        throw StateError(
          'En Windows el login con Google puede fallar.\n'
          'Usá usuario/clave en la PC, o Google desde el celular.\n\n$e',
        );
      }
    }

    throw StateError('Login con Google no soportado en esta plataforma.');
  }

  Future<User> _googleSignInAndroid() async {
    final webClientId = DefaultFirebaseOptions.googleWebClientId.trim();
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: webClientId.isEmpty ? null : webClientId,
    );

    try {
      await googleSignIn.signOut();
    } catch (_) {}

    final account = await googleSignIn.signIn();
    if (account == null) {
      throw StateError('Inicio con Google cancelado.');
    }

    final auth = await account.authentication;
    if ((auth.idToken ?? '').isEmpty) {
      throw StateError(
        'Google no devolvió idToken.\n'
        'Pedile al admin que revise Authentication → Google en Firebase '
        'y el SHA-1 de la app.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user;
    if (user == null || (user.email ?? '').isEmpty) {
      throw StateError('Google no devolvió un email de cuenta.');
    }
    return user;
  }

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

    // Si no hay sesión activa, crear directo en la app principal (más estable en Windows).
    if (_auth.currentUser == null) {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      return cred.user!.uid;
    }

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
      try {
        await secondary.delete();
      } catch (_) {}
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
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
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

  String? get uidActual {
    final auth = _authOrNull;
    if (auth == null) return null;
    try {
      return auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }
}
