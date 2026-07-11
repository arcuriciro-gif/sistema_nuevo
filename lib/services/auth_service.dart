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
import 'comunicaciones_service.dart';

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

  /// Valida la contraseña del usuario en sesión (hash local o clave de login).
  bool verificarPassword(String password) {
    final usuario = currentUser;
    if (usuario == null || password.isEmpty) return false;
    final hash = _hash(password);
    return usuario.password == hash || _ultimaPasswordIngresada == password;
  }

  bool esAdministrador() => RolUtil.esAdministrador(currentUser?.rol);

  Future<Usuario?> login(String usuario, String password) async {
    final nombreUsuario = usuario.trim();
    if (nombreUsuario.isEmpty || password.isEmpty) return null;

    final sqlite = SqliteUsuarioRepository();
    final firebase = FirebaseAuthUsuarioService.instance;
    lastFirebaseError = null;

    var localUser = await sqlite.buscarPorUsuario(nombreUsuario);
    if (localUser == null && nombreUsuario.contains('@')) {
      localUser = await sqlite.buscarPorEmail(nombreUsuario);
    }

    // Si no hay ficha local (ej. otro dispositivo), intentar perfil en Firestore.
    if (localUser == null &&
        BackendConfigService.instance.firebaseEnabled &&
        firebase.disponible) {
      try {
        final remoto =
            await FirestoreUsuarioRepository().buscarPorUsuario(nombreUsuario);
        if (remoto != null) {
          localUser = remoto;
        }
      } catch (e) {
        debugPrint('Buscar usuario remoto previo al login: $e');
      }
    }

    final loginName = (localUser?.usuario ?? nombreUsuario).trim();

    // Si la clave local no coincide (o no hay usuario local), probar Firebase Auth.
    // Así PC y celular pueden usar la misma clave de la nube aunque el hash local difiera.
    final localOk =
        localUser != null && localUser.activo && localUser.password == _hash(password);

    if (!localOk && firebase.disponible) {
      try {
        final cred = await firebase.iniciarSesion(
          loginName,
          password,
          email: localUser?.email,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          if (localUser == null || !localUser.activo || localUser.id == null) {
            // Traer perfil de Firestore o crear ficha local mínima.
            Usuario? remoto;
            try {
              remoto = await FirestoreUsuarioRepository().buscarPorFirebaseUid(uid);
              remoto ??=
                  await FirestoreUsuarioRepository().buscarPorUsuario(loginName);
            } catch (e) {
              debugPrint('Buscar usuario remoto en login: $e');
            }
            final ahora = DateTime.now();
            final nuevo = (remoto ??
                    Usuario(
                      nombre: loginName,
                      usuario: loginName,
                      password: _hash(password),
                      rol: 'empleado',
                      email: cred.user?.email ??
                          UsuarioAuthEmail.paraUsuario(loginName),
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
            final existente = await sqlite.buscarPorUsuario(nuevo.usuario);
            if (existente == null) {
              final id = await sqlite.insertar(nuevo);
              localUser = nuevo.copyWith(id: id);
            } else {
              localUser = nuevo.copyWith(id: existente.id);
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
        lastFirebaseError = FirebaseAuthUsuarioService.mensajeError(e);
      }
    }

    if (localUser == null || !localUser.activo) return null;

    // Si vino de Firestore (sin id local), guardarlo en SQLite para este dispositivo.
    if (localUser.id == null) {
      final existente = await sqlite.buscarPorUsuario(localUser.usuario);
      if (existente != null) {
        localUser = localUser.copyWith(
          id: existente.id,
          password: localUser.password.isNotEmpty
              ? localUser.password
              : existente.password,
        );
        await sqlite.actualizar(localUser);
      } else {
        final id = await sqlite.insertar(localUser);
        localUser = localUser.copyWith(id: id);
      }
    }

    var usuarioActualizado = localUser;
    var autenticado = localUser.password == _hash(password);

    if (!autenticado) return null;

    // Si la clave local/nube (hash) coincide, el login es válido aunque Firebase
    // Auth todavía tenga otra clave vieja (ej. mail de reset).
    lastFirebaseError = null;

    // Vincular / asegurar sesión Firebase si aún no hay uid activo.
    if (firebase.disponible && firebase.uidActual == null) {
      try {
        final cred = await firebase.iniciarSesion(
          usuarioActualizado.usuario,
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
            usuarioActualizado.usuario,
            password,
            email: usuarioActualizado.email,
          );
          if (firebase.uidActual == null) {
            await firebase.iniciarSesion(
              usuarioActualizado.usuario,
              password,
              email: usuarioActualizado.email,
            );
          }
          usuarioActualizado = usuarioActualizado.copyWith(firebaseUid: uid);
          await sqlite.actualizar(usuarioActualizado);
        } catch (createError) {
          debugPrint('Firebase crearCuenta falló: $createError');
          // Login local OK: no bloquear la entrada. La nube se puede reconectar después.
          lastFirebaseError =
              FirebaseAuthUsuarioService.mensajeError(signInError);
          final msgCreate =
              FirebaseAuthUsuarioService.mensajeError(createError);
          if (msgCreate.contains('ya existe') ||
              msgCreate.contains('no coincide')) {
            lastFirebaseError = FirebaseAuthUsuarioService.mensajeError(
              signInError,
            );
            if (!lastFirebaseError!.contains('Contraseña') &&
                !lastFirebaseError!.contains('incorrecta') &&
                !lastFirebaseError!.contains('no coincide')) {
              lastFirebaseError = msgCreate;
            }
          } else {
            lastFirebaseError = msgCreate;
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
      SyncQueueService.instance.clearAuthError();
      debugPrint('Firebase Auth OK uid=$uidActual');
    } else {
      debugPrint(
        'Login local OK, pero sin Firebase Auth. '
        'Revisá Authentication > Correo/contraseña en Firebase.',
      );
      lastFirebaseError ??=
          'Entraste en este dispositivo. La nube quedó pendiente: '
          'tocá el indicador de sync e ingresá de nuevo la misma clave, '
          'o pedile al admin que restablezca la contraseña.';
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

  /// Login con Google. Si no existe usuario, crea solicitud pendiente de alta.
  Future<Usuario> loginConGoogle() async {
    lastFirebaseError = null;
    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) {
      throw StateError('Firebase no está listo en este dispositivo.');
    }

    final googleUser = await firebase.iniciarSesionConGoogle();
    final email = (googleUser.email ?? '').trim().toLowerCase();
    final uid = googleUser.uid;
    final displayName = (googleUser.displayName ?? '').trim();
    if (email.isEmpty) {
      await firebase.cerrarSesion();
      throw StateError('Google no devolvió un email.');
    }

    return _completarAccesoExterno(
      email: email,
      firebaseUid: uid,
      nombreSugerido: displayName.isEmpty ? email.split('@').first : displayName,
      origen: 'google',
    );
  }

  /// Autoregistro / login con correo y clave. Si es nuevo → pendiente de alta.
  Future<Usuario> loginORegistrarConEmail({
    required String email,
    required String password,
    String? nombre,
  }) async {
    lastFirebaseError = null;
    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) {
      throw StateError('Firebase no está listo en este dispositivo.');
    }
    final mail = email.trim().toLowerCase();
    if (!UsuarioAuthEmail.esEmailReal(mail)) {
      throw StateError('Ingresá un email válido (ej. tu Gmail).');
    }
    if (password.trim().length < 6) {
      throw StateError('La contraseña debe tener al menos 6 caracteres.');
    }

    final uid = await firebase.registrarConEmailPassword(mail, password.trim());
    final nombreOk = (nombre ?? '').trim().isEmpty
        ? mail.split('@').first
        : nombre!.trim();

    return _completarAccesoExterno(
      email: mail,
      firebaseUid: uid,
      nombreSugerido: nombreOk,
      origen: 'email',
      passwordPlano: password.trim(),
    );
  }

  Future<Usuario> _completarAccesoExterno({
    required String email,
    required String firebaseUid,
    required String nombreSugerido,
    required String origen,
    String? passwordPlano,
  }) async {
    final firebase = FirebaseAuthUsuarioService.instance;
    final sqlite = SqliteUsuarioRepository();

    var localUser = await sqlite.buscarPorEmail(email);
    if (localUser == null && BackendConfigService.instance.firebaseEnabled) {
      try {
        localUser = await FirestoreUsuarioRepository().buscarPorEmail(email);
      } catch (e) {
        debugPrint('Buscar usuario por email: $e');
      }
    }

    if (localUser == null) {
      final baseUser = await _usuarioLibreDesdeEmail(email);
      final ahora = DateTime.now();
      final pendiente = Usuario(
        firebaseUid: firebaseUid,
        nombre: nombreSugerido,
        usuario: baseUser,
        password: _hash(passwordPlano ?? _hash(email + firebaseUid)),
        rol: 'empleado',
        activo: false,
        pendienteAlta: true,
        debeCambiarPassword: false,
        email: email,
        origenAlta: origen,
        fechaCreacion: ahora,
      );
      final id = await sqlite.insertar(pendiente);
      localUser = pendiente.copyWith(id: id);
      if (BackendConfigService.instance.firebaseEnabled) {
        try {
          await FirestoreUsuarioRepository().insertar(localUser);
          try {
            await ComunicacionesService.instance.crearNotificacion(
              usuarioDestino: 'admin',
              tipo: 'solicitud_alta',
              titulo: 'Solicitud de acceso',
              cuerpo:
                  '$nombreSugerido ($email) pidió acceso con $origen. '
                  'Aprobalo en Usuarios.',
              entidadTipo: 'usuario',
              entidadId: firebaseUid,
            );
          } catch (e) {
            debugPrint('Notif solicitud alta: $e');
          }
        } catch (e) {
          debugPrint('Firestore solicitud alta: $e');
          try {
            await firebase.cerrarSesion();
          } catch (_) {}
          throw StateError(
            'No se pudo enviar la solicitud a la nube.\n'
            'Sin eso el administrador en la PC no la ve.\n\n'
            'Detalle: $e\n\n'
            'Revisá internet y que Firestore permita escribir en '
            'tenants/.../usuarios.',
          );
        }
      }
      try {
        await firebase.cerrarSesion();
      } catch (_) {}
      throw StateError(
        'Solicitud enviada con $email.\n\n'
        'El administrador debe darte el alta en Menú → Usuarios '
        '(badge naranja PENDIENTE ALTA).\n'
        'Cuando te aprueben, volvé a entrar con Google o tu correo.',
      );
    }

    if (localUser.pendienteAlta || !localUser.activo) {
      try {
        await firebase.cerrarSesion();
      } catch (_) {}
      if (localUser.pendienteAlta) {
        throw StateError(
          'Tu acceso todavía está pendiente de aprobación.\n'
          'Pedile al administrador que te dé el alta en Menú → Usuarios ($email).',
        );
      }
      throw StateError(
        'Tu usuario está desactivado. Pedile al administrador que lo reactive.',
      );
    }

    if (localUser.id == null) {
      final existente = await sqlite.buscarPorUsuario(localUser.usuario);
      if (existente != null) {
        localUser = localUser.copyWith(id: existente.id);
        await sqlite.actualizar(localUser);
      } else {
        final id = await sqlite.insertar(localUser);
        localUser = localUser.copyWith(id: id);
      }
    }

    final ahora = DateTime.now();
    final sesion = localUser.copyWith(
      firebaseUid: firebaseUid,
      email: email,
      debeCambiarPassword: false,
      pendienteAlta: false,
      ultimoAcceso: ahora,
      nombre: localUser.nombre.trim().isEmpty
          ? nombreSugerido
          : localUser.nombre,
    );
    await sqlite.actualizar(sesion);
    currentUser = sesion;
    _ultimaPasswordIngresada = passwordPlano;

    if (BackendConfigService.instance.firebaseEnabled) {
      try {
        await FirestoreUsuarioRepository().actualizar(sesion);
      } catch (e) {
        debugPrint('Firestore usuario login externo: $e');
      }
    }

    await FirestoreSyncService.instance.start();
    await SyncQueueService.instance.start();
    SyncQueueService.instance.clearAuthError();

    await _registrarAudit(
      origen == 'google' ? 'LOGIN_GOOGLE' : 'LOGIN_EMAIL',
      'Inicio de sesión ($origen)',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({
        'usuario': sesion.usuario,
        'email': email,
        'rol': sesion.rol,
      }),
    );

    return sesion;
  }

  Future<String> _usuarioLibreDesdeEmail(String email) async {
    final sqlite = SqliteUsuarioRepository();
    var base = email
        .split('@')
        .first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    if (base.isEmpty) base = 'user';
    var candidato = base;
    var i = 1;
    while (await sqlite.existeUsuario(candidato)) {
      candidato = '$base$i';
      i++;
      if (i > 99) {
        candidato = '$base${DateTime.now().millisecondsSinceEpoch}';
        break;
      }
    }
    return candidato;
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

    lastFirebaseError = FirebaseAuthUsuarioService.mensajeError(
      ultimoError ?? 'Error desconocido de Firebase Auth',
    );
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
