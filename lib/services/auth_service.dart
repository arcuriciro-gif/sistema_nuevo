import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
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
        final cred = await firebase.iniciarSesion(
          nombreUsuario,
          password,
          email: usuarioLocal.email,
        );
        final uid = cred.user?.uid;
        if (uid != null && uid != usuarioLocal.firebaseUid) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
        autenticado = true;
      } catch (error) {
        debugPrint('Firebase login falló: $error');
        autenticado = usuarioLocal.password == _hash(password);
      }
    } else if (firebase.disponible && usuarioLocal.password == _hash(password)) {
      autenticado = true;
      try {
        final cred = await firebase.iniciarSesion(
          nombreUsuario,
          password,
          email: usuarioLocal.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
      } catch (signInError) {
        debugPrint('Firebase signIn falló, creando cuenta: $signInError');
        try {
          final uid = await firebase.crearCuenta(
            nombreUsuario,
            password,
            email: usuarioLocal.email,
          );
          usuarioActualizado = usuarioActualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        } catch (createError) {
          debugPrint('Firebase crearCuenta falló: $createError');
          // Cuenta ya creada en otro dispositivo con otra clave:
          // el login local sigue, pero login_page pedirá vincular/cambiar clave.
        }
      }
    } else {
      autenticado = usuarioLocal.password == _hash(password);
    }

    if (!autenticado) return null;

    final ahora = DateTime.now();
    final usuarioSesion = usuarioActualizado.copyWith(ultimoAcceso: ahora);
    await sqlite.actualizar(usuarioSesion);

    currentUser = usuarioSesion;
    _ultimaPasswordIngresada = password;

    // Solo sincronizar / escribir remoto cuando haya sesión Firebase Auth.
    final uidActual = FirebaseAuthUsuarioService.instance.uidActual;
    if (uidActual != null) {
      if (BackendConfigService.instance.firebaseEnabled) {
        try {
          await FirestoreUsuarioRepository().actualizar(usuarioSesion);
        } catch (error) {
          debugPrint('Firestore usuario en login: $error');
        }
      }
      await FirestoreSyncService.instance.start();
      await SyncQueueService.instance.start();
      debugPrint('Firebase Auth OK uid=$uidActual');
    } else {
      debugPrint(
        'Login local OK, pero sin Firebase Auth. '
        'Revisá Authentication > Correo/contraseña en Firebase.',
      );
      // Aun sin Auth remoto, la cola queda lista para cuando haya sesión.
      await SyncQueueService.instance.start();
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
    await SyncQueueService.instance.stop();
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
    if (usuario.password != hashActual &&
        _ultimaPasswordIngresada != passwordActual) {
      throw StateError('La contraseña actual no es correcta.');
    }

    final sqlite = SqliteUsuarioRepository();
    var actualizado = usuario.copyWith(
      password: _hash(passwordNueva),
      debeCambiarPassword: false,
    );
    await sqlite.actualizar(actualizado);
    currentUser = actualizado;
    _ultimaPasswordIngresada = passwordNueva;

    final firebase = FirebaseAuthUsuarioService.instance;
    if (firebase.disponible) {
      final vinculado = await _vincularFirebaseAuth(
        usuario: actualizado,
        passwordPreferida: passwordNueva,
        passwordAlternativa: passwordActual,
      );
      if (vinculado != null) {
        actualizado = vinculado;
        currentUser = actualizado;
      }
    }

    if (BackendConfigService.instance.firebaseEnabled &&
        FirebaseAuthUsuarioService.instance.uidActual != null) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (error) {
        debugPrint('Firestore usuario en cambio password: $error');
      }
      await FirestoreSyncService.instance.start();
      await SyncQueueService.instance.start();
      debugPrint(
        'Firebase Auth OK uid=${FirebaseAuthUsuarioService.instance.uidActual}',
      );
    }

    await registrarCambio(
      'CAMBIO_PASSWORD',
      'usuarios',
      'Cambio de contraseña del usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({'usuario': usuario.usuario}),
      valorNuevo: jsonEncode({
        'usuario': usuario.usuario,
        'fecha': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Intenta crear o iniciar sesión en Firebase Auth. No lanza: si falla, queda local.
  Future<Usuario?> _vincularFirebaseAuth({
    required Usuario usuario,
    required String passwordPreferida,
    String? passwordAlternativa,
  }) async {
    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) return null;
    final sqlite = SqliteUsuarioRepository();

    Future<Usuario?> okConUid(String uid) async {
      final conUid = usuario.copyWith(firebaseUid: uid);
      await sqlite.actualizar(conUid);
      return conUid;
    }

    // 1) Si ya hay sesión, listo.
    final uidActual = firebase.uidActual;
    if (uidActual != null) {
      if (usuario.firebaseUid != uidActual) {
        return okConUid(uidActual);
      }
      return usuario;
    }

    // 2) Probar sign-in con la clave nueva (la que el usuario acaba de elegir).
    try {
      final cred = await firebase.iniciarSesion(
        usuario.usuario,
        passwordPreferida,
        email: usuario.email,
      );
      final uid = cred.user?.uid;
      if (uid != null) return okConUid(uid);
    } catch (e) {
      debugPrint('Firebase signIn (preferida): $e');
    }

    // 3) Probar sign-in con la clave anterior (por si la nube aún no se actualizó).
    if (passwordAlternativa != null &&
        passwordAlternativa.isNotEmpty &&
        passwordAlternativa != passwordPreferida) {
      try {
        final cred = await firebase.iniciarSesion(
          usuario.usuario,
          passwordAlternativa,
          email: usuario.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          try {
            await firebase.cambiarPasswordActual(passwordPreferida);
          } catch (e) {
            debugPrint('Firebase updatePassword: $e');
          }
          return okConUid(uid);
        }
      } catch (e) {
        debugPrint('Firebase signIn (alternativa): $e');
      }
    }

    // 4) Crear cuenta nueva.
    try {
      final uid = await firebase.crearCuenta(
        usuario.usuario,
        passwordPreferida,
        email: usuario.email,
      );
      // crearCuenta sin sesión previa ya deja al usuario logueado.
      if (firebase.uidActual == null) {
        await firebase.iniciarSesion(
          usuario.usuario,
          passwordPreferida,
          email: usuario.email,
        );
      }
      return okConUid(uid);
    } catch (e) {
      debugPrint('Firebase crearCuenta: $e');
    }

    return null;
  }

  /// Actualiza nombre, usuario, email y/o foto del usuario logueado.
  Future<void> actualizarPerfilPropio({
    String? nombre,
    String? usuario,
    String? email,
    String? foto,
    String? passwordActual,
  }) async {
    final actual = currentUser;
    if (actual == null) {
      throw StateError('No hay sesión activa.');
    }
    if (actual.id == null) {
      throw StateError('Usuario inválido.');
    }

    final nuevoUsuario = (usuario ?? actual.usuario).trim();
    final nuevoNombre = (nombre ?? actual.nombre).trim();
    final nuevoEmail = (email ?? actual.email).trim();
    final nuevaFoto = foto ?? actual.foto;

    if (nuevoNombre.isEmpty) {
      throw StateError('El nombre no puede estar vacío.');
    }
    if (nuevoUsuario.isEmpty) {
      throw StateError('El usuario no puede estar vacío.');
    }

    final sqlite = SqliteUsuarioRepository();
    if (nuevoUsuario.toLowerCase() != actual.usuario.toLowerCase()) {
      final existe = await sqlite.buscarPorUsuario(nuevoUsuario);
      if (existe != null && existe.id != actual.id) {
        throw StateError('Ese nombre de usuario ya está en uso.');
      }
      if (passwordActual == null || passwordActual.isEmpty) {
        throw StateError('Ingresá tu contraseña actual para cambiar el usuario.');
      }
      final hashOk = actual.password == _hash(passwordActual) ||
          _ultimaPasswordIngresada == passwordActual;
      if (!hashOk) {
        throw StateError('La contraseña actual no es correcta.');
      }
    }

    var actualizado = actual.copyWith(
      nombre: nuevoNombre,
      usuario: nuevoUsuario,
      email: nuevoEmail,
      foto: nuevaFoto,
    );
    await sqlite.actualizar(actualizado);

    final firebase = FirebaseAuthUsuarioService.instance;
    if (firebase.disponible &&
        (actual.firebaseUid?.isNotEmpty ?? false) &&
        UsuarioAuthEmail.esEmailReal(nuevoEmail) &&
        nuevoEmail.toLowerCase() != actual.email.toLowerCase()) {
      try {
        if (firebase.uidActual == null && passwordActual != null) {
          await firebase.iniciarSesion(
            actual.usuario,
            passwordActual,
            email: actual.email,
          );
        }
        await firebase.actualizarEmailActual(nuevoEmail);
      } catch (e) {
        debugPrint('Firebase update email: $e');
      }
    }

    if (BackendConfigService.instance.firebaseEnabled &&
        (actualizado.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (e) {
        debugPrint('Firestore perfil: $e');
      }
    }

    currentUser = actualizado;
    await registrarCambio(
      'ACTUALIZAR_PERFIL',
      'usuarios',
      'Perfil actualizado: ${actualizado.usuario}',
      valorAnterior: jsonEncode({
        'nombre': actual.nombre,
        'usuario': actual.usuario,
        'email': actual.email,
      }),
      valorNuevo: jsonEncode({
        'nombre': actualizado.nombre,
        'usuario': actualizado.usuario,
        'email': actualizado.email,
      }),
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
