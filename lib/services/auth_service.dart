import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/auth/rol_util.dart';
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/usuario.dart';
import '../repositories/firestore_usuario_repository.dart';
import '../repositories/sqlite_usuario_repository.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  Usuario? currentUser;
  String? _ultimaPasswordIngresada;

  bool get isLoggedIn => currentUser != null;

  static String hashPassword(String password) => _hash(password);

  static String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool esAdministrador() => RolUtil.esAdministrador(currentUser?.rol);

  Future<Usuario?> login(String usuario, String password) async {
    final nombreUsuario = usuario.trim();
    final sqlite = SqliteUsuarioRepository();
    var localUser = await sqlite.buscarPorUsuario(nombreUsuario);

    if (localUser == null || !localUser.activo) return null;

    final usuarioLocal = localUser;
    var autenticado = false;
    final firebase = FirebaseAuthUsuarioService.instance;
    var usuarioActualizado = usuarioLocal;

    if (firebase.disponible && (usuarioLocal.firebaseUid?.isNotEmpty ?? false)) {
      try {
        final cred = await firebase.iniciarSesion(nombreUsuario, password);
        final uid = cred.user?.uid;
        if (uid != null && uid != usuarioLocal.firebaseUid) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
        autenticado = true;
      } catch (_) {
        autenticado = usuarioLocal.password == _hash(password);
      }
    } else if (firebase.disponible && usuarioLocal.password == _hash(password)) {
      autenticado = true;
      try {
        final cred = await firebase.iniciarSesion(nombreUsuario, password);
        final uid = cred.user?.uid;
        if (uid != null) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
      } catch (_) {
        try {
          final uid = await firebase.crearCuenta(nombreUsuario, password);
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        } catch (_) {}
      }
    } else {
      autenticado = usuarioLocal.password == _hash(password);
    }

    if (!autenticado) return null;

    final ahora = DateTime.now();
    final usuarioSesion = usuarioActualizado.copyWith(ultimoAcceso: ahora);
    await sqlite.actualizar(usuarioSesion);

    if (BackendConfigService.instance.firebaseEnabled) {
      try {
        await FirestoreUsuarioRepository().actualizar(usuarioSesion);
      } catch (_) {}
    }

    currentUser = usuarioSesion;
    _ultimaPasswordIngresada = password;

    // Solo sincronizar cuando haya sesión Firebase Auth (reglas de Firestore).
    if (FirebaseAuthUsuarioService.instance.uidActual != null) {
      await FirestoreSyncService.instance.start();
    }

    await _registrarAudit(
      'LOGIN',
      'Inicio de sesión',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({
        'usuario': currentUser?.usuario,
        'rol': currentUser?.rol,
      }),
    );
    return currentUser;
  }

  Future<void> logout() async {
    await _registrarAudit(
      'LOGOUT',
      'Cierre de sesión',
      tablaAfectada: 'usuarios',
      valorAnterior: jsonEncode({'usuario': currentUser?.usuario}),
    );
    currentUser = null;
    _ultimaPasswordIngresada = null;
    await FirestoreSyncService.instance.stop();
    if (FirebaseAuthUsuarioService.instance.disponible) {
      try {
        await FirebaseAuthUsuarioService.instance.cerrarSesion();
      } catch (_) {}
    }
  }

  Future<void> completarCambioPasswordObligatorio(String passwordNueva) async {
    final actual = _ultimaPasswordIngresada;
    if (actual == null || actual.isEmpty) {
      throw StateError('Volvé a iniciar sesión para cambiar la contraseña.');
    }
    await cambiarPasswordPropio(passwordActual: actual, passwordNueva: passwordNueva);
  }

  Future<void> cambiarPasswordPropio({
    required String passwordActual,
    required String passwordNueva,
  }) async {
    final usuario = currentUser;
    if (usuario == null) {
      throw StateError('No hay sesión activa.');
    }

    final hashActual = _hash(passwordActual);
    if (usuario.password != hashActual && _ultimaPasswordIngresada != passwordActual) {
      throw StateError('La contraseña actual no es correcta.');
    }

    final sqlite = SqliteUsuarioRepository();
    final actualizado = usuario.copyWith(
      password: _hash(passwordNueva),
      debeCambiarPassword: false,
    );
    await sqlite.actualizar(actualizado);

    if (BackendConfigService.instance.firebaseEnabled) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (_) {}
    }

    final firebase = FirebaseAuthUsuarioService.instance;
    if (firebase.disponible && (usuario.firebaseUid?.isNotEmpty ?? false)) {
      try {
        if (firebase.uidActual == null) {
          await firebase.iniciarSesion(usuario.usuario, passwordActual);
        }
        await firebase.cambiarPasswordActual(passwordNueva);
      } catch (_) {}
    }

    currentUser = actualizado;
    _ultimaPasswordIngresada = passwordNueva;

    await registrarCambio(
      'CAMBIO_PASSWORD',
      'usuarios',
      'Cambio de contraseña del usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({'usuario': usuario.usuario}),
      valorNuevo: jsonEncode({'usuario': usuario.usuario, 'fecha': DateTime.now().toIso8601String()}),
    );
  }

  Future<void> registrarAccion(String accion, String detalle) async {
    await _registrarAudit(accion, detalle);
  }

  Future<void> registrarCambio(
    String accion,
    String tabla,
    String detalle, {
    String? valorAnterior,
    String? valorNuevo,
  }) async {
    await _registrarAudit(
      accion,
      detalle,
      tablaAfectada: tabla,
      valorAnterior: valorAnterior,
      valorNuevo: valorNuevo,
    );
  }

  Future<void> _registrarAudit(
    String accion,
    String detalle, {
    String? tablaAfectada,
    String? valorAnterior,
    String? valorNuevo,
  }) async {
    if (currentUser == null && accion != 'LOGIN') return;
    final db = await DatabaseHelper.instance.database;
    await db.insert('audit_log', {
      'usuario': currentUser?.usuario ?? 'sistema',
      'accion': accion,
      'detalle': detalle,
      'tablaAfectada': tablaAfectada,
      'valorAnterior': valorAnterior,
      'valorNuevo': valorNuevo,
      'fecha': DateTime.now().toIso8601String(),
    });
  }
}
