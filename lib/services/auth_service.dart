import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
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
  String? lastLoginError;

  bool get isLoggedIn => currentUser != null;

  static String hashPassword(String password) => _hash(password);

  static String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool esAdministrador() => RolUtil.esAdministrador(currentUser?.rol);

  Future<Usuario?> login(String usuario, String password) async {
    lastLoginError = null;
    final entrada = usuario.trim();
    if (entrada.isEmpty || password.isEmpty) {
      lastLoginError = 'Ingresá usuario (o email) y contraseña.';
      return null;
    }

    final sqlite = SqliteUsuarioRepository();
    var localUser = await sqlite.buscarPorUsuario(entrada);
    if (localUser == null && UsuarioAuthEmail.esEmailReal(entrada)) {
      localUser = await sqlite.buscarPorEmail(entrada);
    }

    final firebase = FirebaseAuthUsuarioService.instance;

    // Otra PC / pendrive: no hay usuario local → Auth Firebase + perfil Firestore.
    if ((localUser == null || !localUser.activo) && firebase.disponible) {
      try {
        final cred = await firebase.iniciarSesionFlexible(entrada, password);
        final uid = cred.user?.uid;
        if (uid == null) {
          lastLoginError = 'No se pudo autenticar en Firebase.';
          return null;
        }

        Usuario? remoto;
        try {
          remoto = await FirestoreUsuarioRepository().buscarPorFirebaseUid(uid);
          remoto ??= await FirestoreUsuarioRepository().buscarPorUsuario(entrada);
        } catch (e) {
          debugPrint('Firestore perfil en login remoto: $e');
        }

        if (remoto == null || !remoto.activo) {
          debugPrint('Login remoto OK en Auth pero sin perfil activo en Firestore');
          await firebase.cerrarSesion();
          lastLoginError =
              'Tu cuenta de Firebase existe, pero no hay perfil activo en el sistema. '
              'Pedile al administrador que te dé de alta de nuevo.';
          return null;
        }

        final hidratado = await sqlite.upsertDesdeRemoto(
          remoto.copyWith(
            firebaseUid: uid,
            password: _hash(password),
            debeCambiarPassword: false,
            ultimoAcceso: DateTime.now(),
          ),
        );
        return _finalizarLogin(hidratado, password, sqlite);
      } catch (e) {
        debugPrint('Login remoto Firebase falló: $e');
        lastLoginError =
            'Usuario o contraseña incorrectos. '
            'Si te llegó el mail de confirmación, usá la contraseña que definiste en el enlace '
            '(el enlace abre el navegador; después volvé a la app).';
        return null;
      }
    }

    if (localUser == null || !localUser.activo) {
      lastLoginError = 'Usuario o contraseña incorrectos.';
      return null;
    }

    final usuarioLocal = localUser;
    var autenticado = false;
    var usuarioActualizado = usuarioLocal;
    var firebaseOk = false;

    if (firebase.disponible && (usuarioLocal.firebaseUid?.isNotEmpty ?? false)) {
      try {
        final cred = await firebase.iniciarSesionFlexible(
          usuarioLocal.usuario,
          password,
          emailHint: usuarioLocal.email,
        );
        final uid = cred.user?.uid;
        if (uid != null && uid != usuarioLocal.firebaseUid) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
        autenticado = true;
        firebaseOk = true;
        // Si definieron la clave por el mail de confirmación, alinear hash local.
        if (usuarioLocal.password != _hash(password)) {
          usuarioActualizado = usuarioActualizado.copyWith(
            password: _hash(password),
            debeCambiarPassword: false,
          );
          await sqlite.actualizar(usuarioActualizado);
        }
      } catch (error) {
        debugPrint('Firebase login falló: $error');
        autenticado = usuarioLocal.password == _hash(password);
      }
    } else if (firebase.disponible && usuarioLocal.password == _hash(password)) {
      autenticado = true;
      try {
        final cred = await firebase.iniciarSesionFlexible(
          usuarioLocal.usuario,
          password,
          emailHint: usuarioLocal.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          usuarioActualizado = usuarioLocal.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
          firebaseOk = true;
        }
      } catch (signInError) {
        debugPrint('Firebase signIn falló, creando cuenta: $signInError');
        try {
          final uid = await firebase.crearCuenta(
            usuarioLocal.usuario,
            password,
            email: usuarioLocal.email,
            iniciarSesionDespues: true,
          );
          usuarioActualizado = usuarioActualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
          firebaseOk = true;
        } catch (createError) {
          debugPrint('Firebase crearCuenta falló: $createError');
        }
      }
    } else {
      autenticado = usuarioLocal.password == _hash(password);
    }

    if (!autenticado) {
      lastLoginError =
          'Usuario o contraseña incorrectos. '
          'Si recibiste el email de confirmación, usá la contraseña del enlace '
          '(no la temporal del alta, si ya la cambiaste).';
      return null;
    }

    // Si Auth falló pero el hash local coincide (p.ej. ya cambiaron la clave
    // por el mail), no fingir éxito sin Firebase cuando el usuario ya tiene uid.
    if (!firebaseOk &&
        firebase.disponible &&
        (usuarioActualizado.firebaseUid?.isNotEmpty ?? false)) {
      debugPrint(
        'Hash local OK pero Firebase rechazó la clave. '
        'Probable contraseña definida por email de confirmación.',
      );
      lastLoginError =
          'La contraseña local ya no coincide con Firebase. '
          'Usá la contraseña que definiste en el email de confirmación, '
          'o tocá "Olvidé mi contraseña" para recibir otro enlace.';
      return null;
    }

    return _finalizarLogin(usuarioActualizado, password, sqlite);
  }

  Future<Usuario> _finalizarLogin(
    Usuario usuario,
    String password,
    SqliteUsuarioRepository sqlite,
  ) async {
    final ahora = DateTime.now();
    final usuarioSesion = usuario.copyWith(ultimoAcceso: ahora);
    await sqlite.actualizar(usuarioSesion);

    currentUser = usuarioSesion;
    _ultimaPasswordIngresada = password;

    final uidActual = FirebaseAuthUsuarioService.instance.uidActual;
    if (uidActual != null) {
      if (BackendConfigService.instance.firebaseEnabled) {
        try {
          await FirestoreUsuarioRepository().actualizar(usuarioSesion);
        } catch (error) {
          debugPrint('Firestore usuario en login: $error');
        }
      }
      // No bloquear el login si el sync falla o tarda.
      try {
        await FirestoreSyncService.instance.start();
        debugPrint('Firebase Auth OK uid=$uidActual');
      } catch (error) {
        debugPrint('Sync start en login: $error');
      }
    } else {
      debugPrint(
        'Login local OK, pero sin Firebase Auth. '
        'Revisá Authentication > Correo/contraseña en Firebase.',
      );
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
    return currentUser!;
  }

  /// Envía el mail de restablecimiento (mismo flujo que la confirmación de alta).
  Future<void> enviarRecuperacionPassword(String usuarioOEmail) async {
    final entrada = usuarioOEmail.trim();
    if (entrada.isEmpty) {
      throw StateError('Ingresá tu usuario o email.');
    }
    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) {
      throw StateError('Firebase no está disponible en este dispositivo.');
    }

    final sqlite = SqliteUsuarioRepository();
    var local = await sqlite.buscarPorUsuario(entrada);
    if (local == null && UsuarioAuthEmail.esEmailReal(entrada)) {
      local = await sqlite.buscarPorEmail(entrada);
    }

    final email = local?.email;
    if (local != null) {
      await firebase.enviarRestablecimiento(
        local.usuario,
        email: email,
      );
      return;
    }

    if (!UsuarioAuthEmail.esEmailReal(entrada)) {
      throw StateError(
        'En esta PC no está ese usuario. Ingresá el email con el que te dieron de alta.',
      );
    }
    await firebase.enviarRestablecimiento(entrada, email: entrada);
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
    var actualizado = usuario.copyWith(
      password: _hash(passwordNueva),
      debeCambiarPassword: false,
    );
    await sqlite.actualizar(actualizado);

    final firebase = FirebaseAuthUsuarioService.instance;
    if (firebase.disponible) {
      try {
        if (usuario.firebaseUid?.isNotEmpty ?? false) {
          if (firebase.uidActual == null) {
            await firebase.iniciarSesion(
              usuario.usuario,
              passwordActual,
              email: usuario.email,
            );
          }
          await firebase.cambiarPasswordActual(passwordNueva);
        } else {
          // Primera vez: crear cuenta Firebase con la contraseña nueva (>=6).
          final uid = await firebase.crearCuenta(
            usuario.usuario,
            passwordNueva,
            email: usuario.email,
          );
          actualizado = actualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(actualizado);
        }
      } catch (error) {
        debugPrint('Firebase en cambio de password: $error');
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
      debugPrint('Firebase Auth OK uid=${FirebaseAuthUsuarioService.instance.uidActual}');
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
