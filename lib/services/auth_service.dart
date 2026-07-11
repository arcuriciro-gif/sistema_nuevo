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
  String? lastFirebaseError;

  bool get isLoggedIn => currentUser != null;

  /// Reintenta vincular la sesión actual con Firebase Auth.
  Future<bool> reconectarNube({String? password}) async {
    final usuario = currentUser;
    final pass = (password ?? _ultimaPasswordIngresada ?? '').trim();
    if (usuario == null) {
      lastFirebaseError = 'No hay sesión local.';
      return false;
    }
    if (pass.isEmpty) {
      lastFirebaseError = 'Necesito la contraseña para conectar la nube.';
      return false;
    }
    if (!FirebaseAuthUsuarioService.instance.disponible) {
      lastFirebaseError =
          'Firebase no está listo en este dispositivo. Revisá internet y reiniciá.';
      SyncQueueService.instance.reportAuthError(lastFirebaseError);
      return false;
    }

    lastFirebaseError = null;
    final vinculado = await _vincularFirebaseAuth(
      usuario: usuario,
      passwordPreferida: pass,
    );
    if (vinculado != null &&
        FirebaseAuthUsuarioService.instance.uidActual != null) {
      currentUser = vinculado;
      _ultimaPasswordIngresada = pass;
      try {
        await FirestoreUsuarioRepository().actualizar(vinculado);
      } catch (_) {}
      await FirestoreSyncService.instance.start();
      await SyncQueueService.instance.start();
      SyncQueueService.instance.clearAuthError();
      return true;
    }

    lastFirebaseError ??=
        'No se pudo conectar a la nube. Activá Authentication → Correo/contraseña '
        'y usá la misma clave en ambos dispositivos.';
    SyncQueueService.instance.reportAuthError(lastFirebaseError);
    return false;
  }

  static String hashPassword(String password) => _hash(password);

  static String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool esAdministrador() => RolUtil.esAdministrador(currentUser?.rol);

  Future<Usuario?> login(String usuario, String password) async {
    final nombreUsuario = usuario.trim();
    if (nombreUsuario.isEmpty || password.isEmpty) return null;

    final sqlite = SqliteUsuarioRepository();
    final firebase = FirebaseAuthUsuarioService.instance;
    var localUser = await sqlite.buscarPorUsuario(nombreUsuario);

    // Si la clave local no coincide (o no hay usuario local), probar Firebase Auth.
    // Así PC y celular pueden usar la misma clave de la nube aunque el hash local difiera.
    final localOk =
        localUser != null && localUser.activo && localUser.password == _hash(password);

    if (!localOk && firebase.disponible) {
      try {
        final cred = await firebase.iniciarSesion(
          nombreUsuario,
          password,
          email: localUser?.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          if (localUser == null || !localUser.activo) {
            // Traer perfil de Firestore o crear ficha local mínima.
            Usuario? remoto;
            try {
              remoto = await FirestoreUsuarioRepository().buscarPorFirebaseUid(uid);
              remoto ??=
                  await FirestoreUsuarioRepository().buscarPorUsuario(nombreUsuario);
            } catch (e) {
              debugPrint('Buscar usuario remoto en login: $e');
            }
            final ahora = DateTime.now();
            final nuevo = (remoto ??
                    Usuario(
                      nombre: nombreUsuario,
                      usuario: nombreUsuario,
                      password: _hash(password),
                      rol: 'admin',
                      email: cred.user?.email ??
                          UsuarioAuthEmail.paraUsuario(nombreUsuario),
                      activo: true,
                    ))
                .copyWith(
              password: _hash(password),
              firebaseUid: uid,
              debeCambiarPassword: false,
              activo: true,
              ultimoAcceso: ahora,
              fechaCreacion: remoto?.fechaCreacion ?? ahora,
            );
            if (localUser == null) {
              final id = await sqlite.insertar(nuevo);
              localUser = nuevo.copyWith(id: id);
            } else {
              localUser = nuevo.copyWith(id: localUser.id);
              await sqlite.actualizar(localUser);
            }
          } else {
            // Misma cuenta local, clave de la nube distinta → actualizar hash local.
            localUser = localUser.copyWith(
              password: _hash(password),
              firebaseUid: uid,
              debeCambiarPassword: false,
              activo: true,
            );
            await sqlite.actualizar(localUser);
          }
        }
      } catch (e) {
        debugPrint('Firebase login (clave nube): $e');
      }
    }

    if (localUser == null || !localUser.activo) return null;

    var usuarioActualizado = localUser;
    var autenticado = localUser.password == _hash(password);

    if (!autenticado) return null;

    // Vincular / asegurar sesión Firebase si aún no hay uid activo.
    if (firebase.disponible && firebase.uidActual == null) {
      lastFirebaseError = null;
      try {
        final cred = await firebase.iniciarSesion(
          nombreUsuario,
          password,
          email: usuarioActualizado.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          usuarioActualizado = usuarioActualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        }
      } catch (signInError) {
        debugPrint('Firebase signIn falló, creando cuenta: $signInError');
        try {
          final uid = await firebase.crearCuenta(
            nombreUsuario,
            password,
            email: usuarioActualizado.email,
          );
          if (firebase.uidActual == null) {
            await firebase.iniciarSesion(
              nombreUsuario,
              password,
              email: usuarioActualizado.email,
            );
          }
          usuarioActualizado = usuarioActualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        } catch (createError) {
          debugPrint('Firebase crearCuenta falló: $createError');
          lastFirebaseError =
              FirebaseAuthUsuarioService.mensajeError(createError);
          final msgSignIn =
              FirebaseAuthUsuarioService.mensajeError(signInError);
          if (lastFirebaseError!.contains('ya existe')) {
            lastFirebaseError = msgSignIn;
          }
        }
      }
    } else if (firebase.disponible &&
        firebase.uidActual != null &&
        (usuarioActualizado.firebaseUid == null ||
            usuarioActualizado.firebaseUid!.isEmpty)) {
      usuarioActualizado =
          usuarioActualizado.copyWith(firebaseUid: firebase.uidActual);
      await sqlite.actualizar(usuarioActualizado);
    }

    final ahora = DateTime.now();
    final usuarioSesion = usuarioActualizado.copyWith(ultimoAcceso: ahora);
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
      await FirestoreSyncService.instance.start();
      await SyncQueueService.instance.start();
      debugPrint('Firebase Auth OK uid=$uidActual');
    } else {
      debugPrint(
        'Login local OK, pero sin Firebase Auth. '
        'Revisá Authentication > Correo/contraseña en Firebase.',
      );
      lastFirebaseError ??=
          'Sin sesión en la nube. Activá Authentication → Correo/contraseña '
          'en Firebase Console y tocá el indicador para reconectar.';
      SyncQueueService.instance.reportAuthError(lastFirebaseError);
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
    Object? ultimoError;

    Future<Usuario?> okConUid(String uid) async {
      final conUid = usuario.copyWith(
        firebaseUid: uid,
        password: _hash(passwordPreferida),
        debeCambiarPassword: false,
      );
      await sqlite.actualizar(conUid);
      lastFirebaseError = null;
      return conUid;
    }

    final uidActual = firebase.uidActual;
    if (uidActual != null) {
      if (usuario.firebaseUid != uidActual) {
        return okConUid(uidActual);
      }
      return usuario;
    }

    try {
      final cred = await firebase.iniciarSesion(
        usuario.usuario,
        passwordPreferida,
        email: usuario.email,
      );
      final uid = cred.user?.uid;
      if (uid != null) return okConUid(uid);
    } catch (e) {
      ultimoError = e;
      debugPrint('Firebase signIn (preferida): $e');
    }

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
        ultimoError = e;
        debugPrint('Firebase signIn (alternativa): $e');
      }
    }

    try {
      final uid = await firebase.crearCuenta(
        usuario.usuario,
        passwordPreferida,
        email: usuario.email,
      );
      if (firebase.uidActual == null) {
        await firebase.iniciarSesion(
          usuario.usuario,
          passwordPreferida,
          email: usuario.email,
        );
      }
      return okConUid(uid);
    } catch (e) {
      ultimoError = e;
      debugPrint('Firebase crearCuenta: $e');
    }

    lastFirebaseError = FirebaseAuthUsuarioService.mensajeError(ultimoError!);
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
