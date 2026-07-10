import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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

  Future<UserCredential> iniciarSesion(String usuario, String password) {
    final email = UsuarioAuthEmail.paraUsuario(usuario);
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> cerrarSesion() => _auth.signOut();

  Future<String> crearCuenta(String usuario, String password) async {
    final email = UsuarioAuthEmail.paraUsuario(usuario);
    final appName = 'UsuarioCreator_${DateTime.now().millisecondsSinceEpoch}';
    final secondary = await Firebase.initializeApp(
      name: appName,
      options: _auth.app.options,
    );
    try {
      final cred = await FirebaseAuth.instanceFor(app: secondary)
          .createUserWithEmailAndPassword(email: email, password: password);
      return cred.user!.uid;
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

  Future<void> enviarRestablecimiento(String usuario) async {
    final email = UsuarioAuthEmail.paraUsuario(usuario);
    await _auth.sendPasswordResetEmail(email: email);
  }

  String? get uidActual => _auth.currentUser?.uid;
}
