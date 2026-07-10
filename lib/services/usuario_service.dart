import 'dart:convert';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../models/usuario.dart';
import '../repositories/firestore_usuario_repository.dart';
import '../repositories/sqlite_usuario_repository.dart';
import 'auth_service.dart';

class UsuarioService {
  static final UsuarioService instance = UsuarioService._();
  UsuarioService._();

  SqliteUsuarioRepository get _repoLocal => SqliteUsuarioRepository();

  void _requiereAdministrador() {
    if (!AuthService.instance.esAdministrador()) {
      throw StateError('Solo el administrador puede gestionar usuarios.');
    }
  }

  Future<List<Usuario>> obtenerTodos() async {
    _requiereAdministrador();
    return _repoLocal.obtenerTodos();
  }

  Future<int> insertar(Usuario usuario) async {
    _requiereAdministrador();
    final ahora = DateTime.now();
    final rol = RolUtil.normalizar(usuario.rol);
    final passwordPlano = usuario.password;
    var nuevo = usuario.copyWith(
      rol: rol,
      email: usuario.email.isNotEmpty
          ? usuario.email
          : UsuarioAuthEmail.paraUsuario(usuario.usuario),
      fechaCreacion: usuario.fechaCreacion ?? ahora,
      password: AuthService.hashPassword(passwordPlano),
      debeCambiarPassword: true,
    );

    final firebase = FirebaseAuthUsuarioService.instance;
    if (firebase.disponible) {
      final uid = await firebase.crearCuenta(usuario.usuario, passwordPlano);
      nuevo = nuevo.copyWith(firebaseUid: uid);
      await FirestoreUsuarioRepository().insertar(nuevo);
    }

    final id = await _repoLocal.insertar(nuevo);

    await AuthService.instance.registrarCambio(
      'CREAR_USUARIO',
      'usuarios',
      'Creación de usuario ${nuevo.usuario}',
      valorNuevo: jsonEncode({
        'usuario': nuevo.usuario,
        'rol': nuevo.rol,
        'nombre': nuevo.nombre,
      }),
    );

    return id;
  }

  Future<int> actualizar(Usuario usuario, {String? nuevaPassword}) async {
    _requiereAdministrador();
    final rol = RolUtil.normalizar(usuario.rol);
    var actualizado = usuario.copyWith(rol: rol);

    if (nuevaPassword != null && nuevaPassword.trim().isNotEmpty) {
      actualizado = actualizado.copyWith(
        password: AuthService.hashPassword(nuevaPassword.trim()),
        debeCambiarPassword: true,
      );
    }

    final resultado = await _repoLocal.actualizar(actualizado);

    if (BackendConfigService.instance.firebaseEnabled &&
        (actualizado.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (_) {}
    }

    await AuthService.instance.registrarCambio(
      'MODIFICAR_USUARIO',
      'usuarios',
      'Modificación de usuario ${actualizado.usuario}',
      valorAnterior: jsonEncode({'usuario': usuario.usuario, 'rol': usuario.rol}),
      valorNuevo: jsonEncode({'usuario': actualizado.usuario, 'rol': actualizado.rol}),
    );

    return resultado;
  }

  Future<int> desactivar(int id) async {
    _requiereAdministrador();
    final usuarios = await _repoLocal.obtenerTodos();
    final usuario = usuarios.firstWhere((u) => u.id == id);

    if (usuario.id == AuthService.instance.currentUser?.id) {
      throw StateError('No podés desactivar tu propio usuario.');
    }

    final resultado = await _repoLocal.desactivar(id);

    if (BackendConfigService.instance.firebaseEnabled &&
        (usuario.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository().desactivarPorUid(usuario.firebaseUid!);
      } catch (_) {}
    }

    await AuthService.instance.registrarCambio(
      'DESACTIVAR_USUARIO',
      'usuarios',
      'Desactivación de usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({'activo': true}),
      valorNuevo: jsonEncode({'activo': false}),
    );

    return resultado;
  }

  Future<void> restablecerPassword(Usuario usuario, String nuevaPassword) async {
    _requiereAdministrador();
    if (nuevaPassword.trim().length < 4) {
      throw StateError('La contraseña debe tener al menos 4 caracteres.');
    }

    final actualizado = usuario.copyWith(
      password: AuthService.hashPassword(nuevaPassword.trim()),
      debeCambiarPassword: true,
    );
    await _repoLocal.actualizar(actualizado);

    if (BackendConfigService.instance.firebaseEnabled &&
        (usuario.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (_) {}
    }

    await AuthService.instance.registrarCambio(
      'RESTABLECER_PASSWORD',
      'usuarios',
      'Restablecimiento de contraseña para ${usuario.usuario}',
      valorNuevo: jsonEncode({
        'usuario': usuario.usuario,
        'fecha': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<bool> existeUsuario(String usuario) async {
    return _repoLocal.existeUsuario(usuario);
  }
}
