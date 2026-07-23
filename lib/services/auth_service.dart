import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
import '../core/config/backend_config_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/firebase/firebase_safe_mode.dart';
import '../core/firebase/tenant_membership_service.dart';
import '../core/security/admin_access_policy.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
import '../core/utils/media_path.dart';
import '../database/database_helper.dart';
import '../models/usuario.dart';
import '../repositories/firestore_usuario_repository.dart';
import '../repositories/sqlite_usuario_repository.dart';
import 'app_log.dart';
import 'biometric_auth_service.dart';

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();

  /// Constructor vacío a propósito: NO tocar Firebase/Firestore aquí.
  /// En Windows la nube es opt-in; crear repos Firestore al construir
  /// AuthService rompía el login con [core/no-app].
  AuthService._();

  Usuario? currentUser;
  String? _ultimaPasswordIngresada;
  String? lastLoginError;
  bool _hookSyncRegistrado = false;

  void _asegurarHookSync() {
    if (_hookSyncRegistrado) return;
    try {
      FirestoreSyncService.instance.onUsuarioRemoto =
          _aplicarUsuarioRemotoEnSesion;
      _hookSyncRegistrado = true;
    } catch (e) {
      debugPrint('AuthService: hook sync diferido ($e)');
    }
  }

  /// Login mínimo solo SQLite (último recurso si AuthService/Firebase fallan).
  static Future<Usuario?> loginLocalSoloSqlite(
    String usuario,
    String password,
  ) async {
    final auth = instance;
    auth.lastLoginError = null;
    final entrada = usuario.trim();
    if (entrada.isEmpty || password.isEmpty) {
      auth.lastLoginError = 'Ingresá usuario (o email) y contraseña.';
      return null;
    }

    await DatabaseHelper.instance.database;
    final sqlite = SqliteUsuarioRepository();
    var local = await sqlite.buscarPorUsuario(entrada);

    if (entrada.toLowerCase() == 'admin' && password == 'admin123') {
      final policy = AdminAccessPolicy.instance;
      if (!await policy.isDefaultRecoveryEnabled()) {
        auth.lastLoginError =
            'La clave inicial admin123 ya no está habilitada.\n'
            'Usá tu contraseña o el código de recuperación (Configuración).';
        return null;
      }
      const hashAdmin123 = AdminAccessPolicy.hashAdmin123;
      final ahora = DateTime.now();
      if (local == null) {
        final id = await (await DatabaseHelper.instance.database).insert(
          'usuarios',
          {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password': hashAdmin123,
            'rol': 'admin',
            'activo': 1,
            'debe_cambiar_password': 1,
            'email': 'admin@tata-stock.tatastock.app',
            'fechaCreacion': ahora.toIso8601String(),
            'ultimoAcceso': ahora.toIso8601String(),
          },
        );
        local = Usuario(
          id: id,
          nombre: 'Administrador',
          usuario: 'admin',
          password: hashAdmin123,
          rol: 'admin',
          activo: true,
          debeCambiarPassword: true,
          email: 'admin@tata-stock.tatastock.app',
          fechaCreacion: ahora,
          ultimoAcceso: ahora,
        );
      } else if (!local.activo || local.password != hashAdmin123) {
        local = local.copyWith(
          password: hashAdmin123,
          activo: true,
          rol: 'admin',
          debeCambiarPassword: true,
        );
        await sqlite.actualizar(local);
      } else {
        local = local.copyWith(debeCambiarPassword: true);
        await sqlite.actualizar(local);
      }
      await policy.ensureRecoveryCode();
    }

    if (local == null || !local.activo || local.password != _hash(password)) {
      auth.lastLoginError =
          'Usuario o contraseña incorrectos. Primera vez: admin / admin123.';
      return null;
    }

    auth.currentUser = local.copyWith(ultimoAcceso: DateTime.now());
    auth._ultimaPasswordIngresada = password;
    await sqlite.actualizar(auth.currentUser!);
    await appendAppLog('LOGIN localSoloSqlite OK ${local.usuario}');
    return auth.currentUser;
  }

  void _aplicarUsuarioRemotoEnSesion(Usuario merged) {
    final yo = currentUser;
    if (yo == null) return;
    final sameUid =
        yo.firebaseUid != null && yo.firebaseUid == merged.firebaseUid;
    final sameUser =
        yo.usuario.toLowerCase() == merged.usuario.toLowerCase();
    if (!sameUid && !sameUser) return;
    currentUser = merged.copyWith(password: yo.password);
  }

  bool get isLoggedIn => currentUser != null;

  static String hashPassword(String password) => _hash(password);

  static String _hash(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool esAdministrador() => RolUtil.esAdministrador(currentUser?.rol);

  /// Login local-first: valida SQLite y entra YA.
  /// Firebase/sync se conectan después con [conectarFirebaseDespuesDelLogin]
  /// para que un crash nativo de Firebase no tumbe el ingreso.
  Future<Usuario?> login(String usuario, String password) async {
    lastLoginError = null;
    final entrada = usuario.trim();
    if (entrada.isEmpty || password.isEmpty) {
      lastLoginError = 'Ingresá usuario (o email) y contraseña.';
      return null;
    }

    try {
      return await _loginInterno(entrada, password);
    } catch (e, st) {
      debugPrint('LOGIN exception: $e\n$st');
      await appendAppLog('LOGIN exception: $e\n$st');
      lastLoginError =
          'No se pudo iniciar sesión (dato local).\n'
          'Si es la primera vez en esta PC, cerrá la app y abrila con '
          'ABRIR_TATA_MANAGER.bat desde la carpeta completa.\n'
          'Detalle: $e';
      return null;
    }
  }

  Future<Usuario?> _loginInterno(String entrada, String password) async {
    // Asegura DB + usuario admin seed antes de validar.
    await DatabaseHelper.instance.database;

    final sqlite = SqliteUsuarioRepository();
    var localUser = await sqlite.buscarPorUsuario(entrada);
    if (localUser == null && UsuarioAuthEmail.esEmailReal(entrada)) {
      localUser = await sqlite.buscarPorEmail(entrada);
    }

    // Recuperación controlada: admin/admin123 solo si la política lo permite.
    if (entrada.toLowerCase() == 'admin' && password == 'admin123') {
      final policy = AdminAccessPolicy.instance;
      if (!await policy.isDefaultRecoveryEnabled()) {
        lastLoginError =
            'La clave inicial admin123 ya no está habilitada.\n'
            'Usá tu contraseña o recuperá con el código de seguridad.';
        return null;
      }
      if (localUser == null ||
          !localUser.activo ||
          localUser.password != _hash(password)) {
        final db = await DatabaseHelper.instance.database;
        const hashAdmin123 = AdminAccessPolicy.hashAdmin123;
        final ahora = DateTime.now();
        if (localUser == null) {
          final id = await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password': hashAdmin123,
            'rol': 'admin',
            'activo': 1,
            'debe_cambiar_password': 1,
            'email': 'admin@tata-stock.tatastock.app',
            'fechaCreacion': ahora.toIso8601String(),
            'ultimoAcceso': ahora.toIso8601String(),
          });
          localUser = Usuario(
            id: id,
            nombre: 'Administrador',
            usuario: 'admin',
            password: hashAdmin123,
            rol: 'admin',
            activo: true,
            debeCambiarPassword: true,
            email: 'admin@tata-stock.tatastock.app',
            fechaCreacion: ahora,
            ultimoAcceso: ahora,
          );
        } else {
          localUser = localUser.copyWith(
            password: hashAdmin123,
            activo: true,
            rol: 'admin',
            debeCambiarPassword: true,
          );
          await sqlite.actualizar(localUser);
        }
        await appendAppLog('LOGIN admin local reparado (recovery default)');
      } else {
        localUser = localUser.copyWith(debeCambiarPassword: true);
        await sqlite.actualizar(localUser);
      }
      await policy.ensureRecoveryCode();
    }

    final firebase = FirebaseAuthUsuarioService.instance;
    // Nunca tocamos Firebase Auth si el app no está listo (evita [core/no-app] en .exe).
    final puedeFirebase = !FirebaseSafeMode.enabled &&
        BackendConfigService.instance.firebaseEnabled &&
        firebase.disponible;

    await appendAppLog(
      'LOGIN start entrada=$entrada '
      'local=${localUser != null} puedeFirebase=$puedeFirebase '
      'fbReady=${FirebaseBootstrap.isReady} '
      'db=${await DatabaseHelper.instance.dbFilePath}',
    );

    // Sin usuario local: solo posible vía Firebase (otra PC / pendrive).
    if (localUser == null || !localUser.activo) {
      if (!puedeFirebase) {
        lastLoginError = FirebaseSafeMode.enabled
            ? 'Modo seguro activo (la app se cerró antes con Firebase). '
                'Entrá con un usuario local (ej. admin) o desactivá el modo seguro.'
            : 'Usuario o contraseña incorrectos. '
                'Primera vez en esta PC: admin / admin123.';
        return null;
      }
      try {
        await FirebaseSafeMode.marcarInicioLoginFirebase();
        final cred = await firebase.iniciarSesionFlexible(entrada, password);
        final uid = cred.user?.uid;
        if (uid == null) {
          await FirebaseSafeMode.marcarFinLoginFirebase();
          lastLoginError = 'No se pudo autenticar en Firebase.';
          return null;
        }

        Usuario? remoto;
        try {
          remoto = await FirestoreUsuarioRepository().buscarPorFirebaseUid(uid);
          remoto ??=
              await FirestoreUsuarioRepository().buscarPorUsuario(entrada);
        } catch (e) {
          debugPrint('Firestore perfil en login remoto: $e');
        }

        if (remoto == null || !remoto.activo) {
          await firebase.cerrarSesion();
          await FirebaseSafeMode.marcarFinLoginFirebase();
          lastLoginError =
              'Tu cuenta de Firebase existe, pero no hay perfil activo en el sistema. '
              'Pedile al administrador que te dé de alta de nuevo.';
          return null;
        }

        final miembroOk =
            await TenantMembershipService.instance.esMiembroActivo(uid);
        if (!miembroOk) {
          await firebase.cerrarSesion();
          await FirebaseSafeMode.marcarFinLoginFirebase();
          lastLoginError =
              'Ya no tenés acceso a esta empresa. '
              'El administrador te quitó del sistema.';
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
        await FirebaseSafeMode.marcarFinLoginFirebase();
        return _finalizarLoginLocal(hidratado, password, sqlite);
      } catch (e) {
        await FirebaseSafeMode.marcarFinLoginFirebase();
        debugPrint('Login remoto Firebase falló: $e');
        lastLoginError =
            'Usuario o contraseña incorrectos. '
            'Si te llegó el mail de confirmación, usá la contraseña del enlace. '
            'Sin nube en esta PC: admin / admin123.';
        return null;
      }
    }

    // Usuario local: validar hash y entrar sin tocar Firebase todavía.
    if (localUser.password != _hash(password)) {
      // Si la clave local no coincide, probar Firebase (clave del mail).
      if (puedeFirebase) {
        try {
          await FirebaseSafeMode.marcarInicioLoginFirebase();
          final cred = await firebase.iniciarSesionFlexible(
            localUser.usuario,
            password,
            emailHint: localUser.email,
          );
          final uid = cred.user?.uid;
          if (uid != null) {
            final actualizado = localUser.copyWith(
              firebaseUid: uid,
              password: _hash(password),
              debeCambiarPassword: false,
            );
            await sqlite.actualizar(actualizado);
            await FirebaseSafeMode.marcarFinLoginFirebase();
            return _finalizarLoginLocal(actualizado, password, sqlite);
          }
        } catch (e) {
          debugPrint('Firebase login (clave distinta a local): $e');
        } finally {
          await FirebaseSafeMode.marcarFinLoginFirebase();
        }
      }
      lastLoginError =
          'Usuario o contraseña incorrectos. '
          'Si recibiste el email de confirmación, usá la contraseña del enlace.';
      return null;
    }

    await appendAppLog('LOGIN local OK user=${localUser.usuario}');
    return _finalizarLoginLocal(localUser, password, sqlite);
  }

  Future<Usuario> _finalizarLoginLocal(
    Usuario usuario,
    String password,
    SqliteUsuarioRepository sqlite,
  ) async {
    await appendAppLog('LOGIN finalizar local ${usuario.usuario}');
    _asegurarHookSync();
    var sesion = usuario;
    // Clave inicial: siempre obligar cambio.
    if (password == 'admin123' &&
        usuario.usuario.toLowerCase() == 'admin') {
      sesion = sesion.copyWith(debeCambiarPassword: true);
      await AdminAccessPolicy.instance.ensureRecoveryCode();
    }
    final ahora = DateTime.now();
    final usuarioSesion = sesion.copyWith(ultimoAcceso: ahora);
    await sqlite.actualizar(usuarioSesion);

    currentUser = usuarioSesion;
    _ultimaPasswordIngresada = password;

    await _registrarAudit(
      'LOGIN',
      'Inicio de sesión',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({
        'usuario': currentUser?.usuario,
        'rol': currentUser?.rol,
      }),
    );
    await appendAppLog('LOGIN listo (sin Firebase en este paso)');
    return currentUser!;
  }

  /// Conecta Firebase Auth + sync si la nube ya está habilitada.
  Future<({bool ok, String mensaje})> conectarFirebaseDespuesDelLogin() async {
    if (!BackendConfigService.instance.firebaseEnabled) {
      await appendAppLog('POST-LOGIN nube desactivada (opt-in pendiente)');
      return (ok: false, mensaje: 'Nube desactivada.');
    }
    return _conectarFirebaseInterno();
  }

  /// Opt-in del usuario desde Configuración.
  Future<({bool ok, String mensaje})> activarNube({
    String? passwordOverride,
  }) async {
    await FirebaseSafeMode.desactivar();
    await BackendConfigService.instance.setFirebaseEnabled(true);
    return _conectarFirebaseInterno(passwordOverride: passwordOverride);
  }

  Future<({bool ok, String mensaje})> _conectarFirebaseInterno({
    String? passwordOverride,
  }) async {
    final usuario = currentUser;
    final password = (passwordOverride ?? _ultimaPasswordIngresada)?.trim();
    if (usuario == null || password == null || password.isEmpty) {
      return (
        ok: false,
        mensaje: 'Volvé a iniciar sesión para conectar la nube.',
      );
    }
    if (FirebaseSafeMode.enabled) {
      return (
        ok: false,
        mensaje:
            'Modo seguro activo. Desactivalo en Configuración e intentá de nuevo.',
      );
    }

    try {
      if (!FirebaseBootstrap.isReady) {
        await FirebaseBootstrap.initializeIfNeeded();
      }
    } catch (e) {
      await appendAppLog('Firebase init post-login: $e');
      await FirebaseSafeMode.activar();
      await BackendConfigService.instance.setFirebaseEnabled(false);
      return (
        ok: false,
        mensaje: 'No se pudo iniciar Firebase: $e',
      );
    }

    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) {
      return (ok: false, mensaje: 'Firebase no está disponible.');
    }

    try {
      await FirebaseSafeMode.marcarInicioLoginFirebase();

      if (firebase.uidActual == null) {
        try {
          final cred = await firebase.iniciarSesionFlexible(
            usuario.usuario,
            password,
            emailHint: usuario.email,
          );
          final uid = cred.user?.uid;
          if (uid != null && uid != usuario.firebaseUid) {
            final actualizado = usuario.copyWith(firebaseUid: uid);
            await SqliteUsuarioRepository().actualizar(actualizado);
            currentUser = actualizado;
          }
        } catch (signInError) {
          debugPrint('Firebase signIn post-login: $signInError');
          final signInTexto = '$signInError';
          final claveIncorrecta = signInTexto.contains('wrong-password') ||
              signInTexto.contains('invalid-credential') ||
              signInTexto.contains('INVALID_LOGIN_CREDENTIALS');
          if (claveIncorrecta) {
            await FirebaseSafeMode.marcarFinLoginFirebase();
            return (
              ok: false,
              mensaje:
                  'CUENTA_NUBE_EXISTE: La contraseña no coincide con la de la nube. '
                  'Entrá con la MISMA clave que en la PC (o restablecela) '
                  'y volvé a activar la sincronización.\n\n'
                  'Google solo sirve si el usuario tiene Gmail real cargado; '
                  'admin sin Gmail usa usuario/clave.',
            );
          }
          try {
            final uid = await firebase.crearCuenta(
              usuario.usuario,
              password,
              email: usuario.email,
              iniciarSesionDespues: true,
            );
            final actualizado =
                (currentUser ?? usuario).copyWith(firebaseUid: uid);
            await SqliteUsuarioRepository().actualizar(actualizado);
            currentUser = actualizado;
          } catch (createError) {
            debugPrint('Firebase crearCuenta post-login: $createError');
            await FirebaseSafeMode.marcarFinLoginFirebase();
            final texto = '$createError';
            final yaExiste = texto.contains('email-already-in-use');
            return (
              ok: false,
              mensaje: yaExiste
                  ? 'CUENTA_NUBE_EXISTE: La cuenta ya existe en la nube '
                      '(creada en la PC). Usá la MISMA contraseña que en la PC '
                      'para activar la sincronización.\n\n'
                      'Google solo funciona si ese usuario tiene un Gmail real '
                      'cargado por el admin; admin sin Gmail entra con usuario/clave.'
                  : 'No se pudo autenticar en la nube. '
                      'Revisá usuario/clave o el mail de confirmación. ($createError)',
            );
          }
        }
      }

      if (passwordOverride != null && passwordOverride.trim().isNotEmpty) {
        _ultimaPasswordIngresada = passwordOverride.trim();
      }

      final uidActual = firebase.uidActual;
      if (uidActual != null) {
        try {
          await FirestoreUsuarioRepository().actualizar(currentUser!);
        } catch (e) {
          debugPrint('Firestore usuario post-login: $e');
        }
        try {
          await TenantMembershipService.instance.asegurarMembresia(
            rol: currentUser!.rol,
            email: currentUser!.email,
            usuario: currentUser!.usuario,
          );
        } catch (e) {
          debugPrint('Membership post-login: $e');
        }
        try {
          await FirestoreSyncService.instance.start();
          await appendAppLog('Firebase Auth OK uid=$uidActual');
        } catch (e) {
          debugPrint('Sync start post-login: $e');
        }
        await FirebaseSafeMode.marcarFinLoginFirebase();
        return (
          ok: true,
          mensaje:
              'Sincronización activada. Las ventas/productos/fotos se comparten con el celular.',
        );
      }

      await FirebaseSafeMode.marcarFinLoginFirebase();
      return (
        ok: false,
        mensaje: 'No quedó sesión Firebase. Probá cerrar sesión y volver a entrar.',
      );
    } catch (e) {
      await FirebaseSafeMode.marcarFinLoginFirebase();
      await appendAppLog('conectarFirebase error: $e');
      return (ok: false, mensaje: 'Error al conectar: $e');
    }
  }

  Future<void> desactivarNube() async {
    try {
      await FirestoreSyncService.instance.stop();
    } catch (_) {}
    try {
      await FirebaseAuthUsuarioService.instance.cerrarSesion();
    } catch (_) {}
    await BackendConfigService.instance.setFirebaseEnabled(false);
    await appendAppLog('Nube desactivada por el usuario');
  }

  /// Envía el mail de restablecimiento (mismo flujo que la confirmación de alta).
  Future<void> enviarRecuperacionPassword(String usuarioOEmail) async {
    final entrada = usuarioOEmail.trim();
    if (entrada.isEmpty) {
      throw StateError('Ingresá tu usuario o email.');
    }
    if (FirebaseSafeMode.enabled) {
      throw StateError(
        'Modo seguro activo. Reiniciá tras desactivarlo, o usá un usuario local.',
      );
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

  /// Login con Google: el Gmail debe coincidir con un usuario dado de alta.
  Future<Usuario> loginConGoogle() async {
    // En Android/Windows, Google requiere Firebase activo.
    if (!BackendConfigService.instance.firebaseEnabled) {
      await BackendConfigService.instance.setFirebaseEnabled(true);
    }
    if (FirebaseSafeMode.enabled) {
      throw StateError(
        'Modo seguro activo. Desactivalo en el login o Configuración.',
      );
    }
    try {
      if (!FirebaseBootstrap.isReady) {
        await FirebaseBootstrap.initializeIfNeeded();
      }
    } catch (e) {
      await FirebaseSafeMode.activar();
      await BackendConfigService.instance.setFirebaseEnabled(false);
      throw StateError('No se pudo iniciar Firebase para Google: $e');
    }

    final firebase = FirebaseAuthUsuarioService.instance;
    if (!firebase.disponible) {
      throw StateError('Firebase no está listo en este dispositivo.');
    }

    final googleUser = await firebase.iniciarSesionConGoogle();
    final email = (googleUser.email ?? '').trim().toLowerCase();
    final uid = googleUser.uid;
    if (email.isEmpty) {
      await firebase.cerrarSesion();
      throw StateError('Google no devolvió un email.');
    }

    final sqlite = SqliteUsuarioRepository();
    var localUser = await sqlite.buscarPorEmail(email);

    if (localUser == null && BackendConfigService.instance.firebaseEnabled) {
      try {
        localUser = await FirestoreUsuarioRepository().buscarPorEmail(email);
      } catch (e) {
        debugPrint('Buscar usuario por email (Google): $e');
      }
    }

    if (localUser == null || !localUser.activo) {
      try {
        await firebase.cerrarSesion();
      } catch (_) {}
      throw StateError(
        'El Gmail $email no está dado de alta en Tata.Manager.\n\n'
        'Pedile al administrador que cree tu usuario y ponga exactamente '
        'ese email en el campo Email.',
      );
    }

    if (localUser.id == null) {
      final existente = await sqlite.buscarPorUsuario(localUser.usuario);
      if (existente != null) {
        localUser = localUser.copyWith(
          id: existente.id,
          password: existente.password.isNotEmpty
              ? existente.password
              : localUser.password,
        );
        await sqlite.actualizar(localUser);
      } else {
        final id = await sqlite.insertar(localUser);
        localUser = localUser.copyWith(id: id);
      }
    }

    final ahora = DateTime.now();
    final sesion = localUser.copyWith(
      firebaseUid: uid,
      email: email,
      debeCambiarPassword: false,
      ultimoAcceso: ahora,
      nombre: localUser.nombre.trim().isEmpty
          ? (googleUser.displayName ?? localUser.usuario)
          : localUser.nombre,
    );
    await sqlite.actualizar(sesion);
    currentUser = sesion;
    _ultimaPasswordIngresada = null;

    if (BackendConfigService.instance.firebaseEnabled) {
      try {
        await FirestoreUsuarioRepository().actualizar(sesion);
      } catch (e) {
        debugPrint('Firestore usuario Google login: $e');
      }
      try {
        await TenantMembershipService.instance.asegurarMembresia(
          rol: sesion.rol,
          email: sesion.email,
          usuario: sesion.usuario,
        );
      } catch (e) {
        debugPrint('Membership Google login: $e');
      }
      try {
        await FirestoreSyncService.instance.start();
      } catch (e) {
        debugPrint('Sync start Google login: $e');
      }
    }

    await _registrarAudit(
      'LOGIN_GOOGLE',
      'Inicio de sesión con Google',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({
        'usuario': sesion.usuario,
        'email': email,
        'rol': sesion.rol,
      }),
    );

    return sesion;
  }

  /// Recupera el admin local con el código de un solo uso.
  /// Devuelve una contraseña temporal; el login siguiente exige cambio.
  Future<String?> recuperarAdminConCodigo(String codigo) async {
    final policy = AdminAccessPolicy.instance;
    if (!await policy.validateRecoveryCode(codigo)) {
      return null;
    }

    await DatabaseHelper.instance.database;
    final sqlite = SqliteUsuarioRepository();
    var admin = await sqlite.buscarPorUsuario('admin');
    if (admin == null) {
      return null;
    }

    final temp = _generarPasswordTemporal();
    admin = admin.copyWith(
      password: _hash(temp),
      debeCambiarPassword: true,
      activo: true,
      rol: 'admin',
      ultimoAcceso: DateTime.now(),
    );
    await sqlite.actualizar(admin);
    await policy.disableDefaultRecovery();
    await policy.rotateRecoveryCode();

    await _registrarAudit(
      'ADMIN_RECOVERY',
      'Recuperación de admin con código',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({'usuario': 'admin'}),
    );
    return temp;
  }

  Future<String?> codigoRecuperacionAdminVisible() =>
      AdminAccessPolicy.instance.peekRecoveryCodePlain();

  Future<String?> asegurarCodigoRecuperacionAdmin() =>
      AdminAccessPolicy.instance.ensureRecoveryCode();

  Future<void> ocultarCodigoRecuperacionAdmin() =>
      AdminAccessPolicy.instance.clearRecoveryCodePlain();

  String _generarPasswordTemporal() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer('Tmp');
    var x = rnd;
    for (var i = 0; i < 9; i++) {
      buf.write(alphabet[x % alphabet.length]);
      x = (x ~/ alphabet.length) + 17 + i * 31;
    }
    return buf.toString();
  }

  Future<void> logout({bool olvidarHuella = false}) async {
    await _registrarAudit(
      'LOGOUT',
      'Cierre de sesión',
      tablaAfectada: 'usuarios',
      valorAnterior: jsonEncode({'usuario': currentUser?.usuario}),
    );
    currentUser = null;
    _ultimaPasswordIngresada = null;
    await FirestoreSyncService.instance.stop();
    if (olvidarHuella) {
      await BiometricAuthService.instance.desactivar();
    }
    // Si queda huella activa, NO cerramos Firebase Auth: así al volver a
    // entrar con huella la nube sigue conectada y los clientes del APK suben.
    final bioSigue =
        !olvidarHuella && await BiometricAuthService.instance.estaActivada();
    if (!bioSigue && FirebaseAuthUsuarioService.instance.disponible) {
      try {
        await FirebaseAuthUsuarioService.instance.cerrarSesion();
      } catch (_) {}
    }
  }

  /// Restaura la sesión local tras biometría (el usuario ya se había logueado).
  Future<Usuario> loginConHuella() async {
    lastLoginError = null;
    final bio = BiometricAuthService.instance;
    if (!await bio.estaActivada()) {
      throw StateError(
        'El desbloqueo biométrico no está activado. '
        'Entrá con usuario y activalo en Mi perfil.',
      );
    }
    final ok = await bio.autenticar(
      motivo: 'Entrar a Tata.Manager con huella, rostro o desbloqueo del celular',
    );
    if (!ok) {
      throw Exception(
        bio.lastError ??
            'No se pudo verificar la identidad. Probá de nuevo.',
      );
    }
    final userId = await bio.usuarioIdGuardado();
    if (userId == null) {
      throw StateError('No hay usuario guardado para biometría.');
    }
    final sqlite = SqliteUsuarioRepository();
    final user = await sqlite.buscarPorId(userId);
    if (user == null) {
      await bio.desactivar();
      throw StateError('El usuario ya no existe. Entrá de nuevo.');
    }
    if (!user.activo) {
      throw StateError('Tu usuario no está activo.');
    }

    final ahora = DateTime.now();
    final sesion = user.copyWith(ultimoAcceso: ahora);
    await sqlite.actualizar(sesion);
    currentUser = sesion;

    if (BackendConfigService.instance.firebaseEnabled) {
      final uidActual = FirebaseAuthUsuarioService.instance.uidActual;
      if (uidActual != null) {
        try {
          await FirestoreSyncService.instance.start();
        } catch (e) {
          debugPrint('Sync post-huella: $e');
        }
      } else {
        FirestoreSyncService.instance.syncStatusLabel = 'Sin nube';
        FirestoreSyncService.instance.syncStatusDetail =
            'Entrá una vez con usuario y contraseña para conectar la nube. '
            'Después la huella mantiene la sync.';
      }
    }

    await _registrarAudit(
      'LOGIN_BIOMETRIA',
      'Inicio de sesión con biometría',
      tablaAfectada: 'usuarios',
      valorNuevo: jsonEncode({
        'usuario': currentUser?.usuario,
        'rol': currentUser?.rol,
      }),
    );
    return sesion;
  }

  /// Ofrece guardar el usuario actual para desbloqueo biométrico.
  Future<void> activarDesbloqueoHuella() async {
    final u = currentUser;
    if (u?.id == null) {
      throw StateError('Tenés que estar logueado.');
    }
    final bio = BiometricAuthService.instance;
    if (!await bio.dispositivoSoporta()) {
      throw StateError('Este dispositivo no soporta biometría / desbloqueo.');
    }
    if (!await bio.tieneHuellaOBiometria()) {
      throw StateError(
        'Configurá huella, rostro o PIN/patrón en Ajustes del celular y reintentá.',
      );
    }
    final ok = await bio.autenticar(
      motivo: 'Confirmá para activar el desbloqueo rápido',
    );
    if (!ok) {
      throw Exception(
        bio.lastError ??
            'No se confirmó la identidad. Probá de nuevo o usá el PIN del celular.',
      );
    }
    await bio.activarParaUsuario(u!.id!);
  }

  /// Mensaje limpio para SnackBars (sin "Bad state:" / "Exception:").
  static String mensajeUsuario(Object e) {
    return e
        .toString()
        .replaceFirst(RegExp(r'^(Bad state: |Exception: |StateError: )'), '');
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
    if (firebase.disponible && !FirebaseSafeMode.enabled) {
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
        !FirebaseSafeMode.enabled &&
        FirebaseAuthUsuarioService.instance.uidActual != null) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (error) {
        debugPrint('Firestore usuario en cambio password: $error');
      }
      try {
        await FirestoreSyncService.instance.start();
      } catch (error) {
        debugPrint('Sync en cambio password: $error');
      }
      debugPrint('Firebase Auth OK uid=${FirebaseAuthUsuarioService.instance.uidActual}');
    }

    currentUser = actualizado;
    _ultimaPasswordIngresada = passwordNueva;

    // Tras salir de admin123, cerrar el backdoor por defecto.
    if (usuario.usuario.toLowerCase() == 'admin' &&
        passwordActual == 'admin123' &&
        passwordNueva != 'admin123') {
      await AdminAccessPolicy.instance.disableDefaultRecovery();
      await AdminAccessPolicy.instance.ensureRecoveryCode();
    }

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

    // Subir foto a Storage si es local y hay nube.
    if (BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady &&
        nuevaFoto.isNotEmpty &&
        !esUrlRemota(nuevaFoto)) {
      final key = actual.firebaseUid?.isNotEmpty == true
          ? actual.firebaseUid!
          : (FirebaseAuthUsuarioService.instance.uidActual ?? actual.usuario);
      final file = File(nuevaFoto);
      if (!file.existsSync()) {
        throw Exception('No se encontró la foto de perfil en este dispositivo.');
      }
      final url = await MediaSyncService.instance.subirFotoUsuario(
        uidOrUsuario: key,
        file: file,
      );
      if (url == null) {
        throw Exception(
          'No se pudo subir la foto de perfil a la nube. '
          '${MediaSyncService.instance.lastError ?? "Revisá la conexión."}',
        );
      }
      actualizado = actualizado.copyWith(foto: url);
    }

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
        FirebaseBootstrap.isReady) {
      try {
        // Asegurar firebaseUid desde Auth si falta.
        if ((actualizado.firebaseUid == null ||
                actualizado.firebaseUid!.isEmpty) &&
            firebase.uidActual != null) {
          actualizado =
              actualizado.copyWith(firebaseUid: firebase.uidActual);
          await sqlite.actualizar(actualizado);
        }
        await FirestoreSyncService.instance.subirUsuario(actualizado);
      } catch (e) {
        throw Exception(
          'Perfil guardado en este equipo, pero no se sincronizó: '
          '${mensajeUsuario(e)}',
        );
      }
    }

    currentUser = actualizado;
    DataRefreshHub.instance.notifyUsuarios();
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
    try {
      if (currentUser == null &&
          accion != 'LOGIN' &&
          accion != 'ADMIN_RECOVERY') {
        return;
      }
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
    } catch (e) {
      debugPrint('audit_log omitido: $e');
    }
  }
}
