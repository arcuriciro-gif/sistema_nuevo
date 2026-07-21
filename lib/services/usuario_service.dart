import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/firebase/tenant_membership_service.dart';
import '../models/usuario.dart';
import '../repositories/firestore_usuario_repository.dart';
import '../repositories/sqlite_usuario_repository.dart';
import 'auth_service.dart';
import 'branding_service.dart';
import 'comunicaciones_service.dart';

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

  /// Resultado del alta: id local + si se envió email de confirmación.
  Future<({int id, bool emailEnviado, String? aviso})> insertarConAviso(
    Usuario usuario, {
    bool enviarEmailConfirmacion = false,
  }) async {
    _requiereAdministrador();
    final ahora = DateTime.now();
    final rol = RolUtil.normalizar(usuario.rol);
    final passwordPlano = usuario.password;
    final emailReal = usuario.email.trim();
    final emailAuth = UsuarioAuthEmail.esEmailReal(emailReal)
        ? emailReal
        : UsuarioAuthEmail.paraUsuario(usuario.usuario);
    var nuevo = usuario.copyWith(
      rol: rol,
      email: emailAuth,
      fechaCreacion: usuario.fechaCreacion ?? ahora,
      password: AuthService.hashPassword(passwordPlano),
      // Clave definida por el admin: puede entrar ya; opcional forzar cambio.
      debeCambiarPassword: usuario.debeCambiarPassword,
    );

    final firebase = FirebaseAuthUsuarioService.instance;
    var emailEnviado = false;
    String? aviso;
    if (firebase.disponible) {
      final uid = await firebase.crearCuenta(
        usuario.usuario,
        passwordPlano,
        email: emailAuth,
        // No pisar la sesión Firebase del administrador.
        iniciarSesionDespues: false,
      );
      nuevo = nuevo.copyWith(firebaseUid: uid);
      await FirestoreUsuarioRepository().insertar(nuevo);

      final memberOk =
          await TenantMembershipService.instance.invitarOActualizarMiembro(
        uid: uid,
        rol: rol,
        email: emailAuth,
        usuario: usuario.usuario,
        activo: nuevo.activo,
      );
      if (!memberOk) {
        aviso =
            'Usuario creado, pero no se pudo registrar el permiso en la nube. '
            'Revisá que la sincronización esté activa como administrador.';
      }

      if (enviarEmailConfirmacion && UsuarioAuthEmail.esEmailReal(emailReal)) {
        try {
          await firebase.enviarConfirmacionAlta(
            usuario: usuario.usuario,
            email: emailReal,
          );
          emailEnviado = true;
          aviso =
              'Usuario creado. Se envió un email a $emailReal para que elija clave.\n'
              'Si no usa el email, puede entrar con usuario ${usuario.usuario} '
              'y la clave que definiste.';
        } catch (e) {
          debugPrint('Email confirmación alta: $e');
          aviso =
              'Usuario creado con clave definida por vos. '
              'No se pudo enviar el email de confirmación.';
        }
      } else {
        aviso ??=
            'Usuario "${usuario.usuario}" creado.\n\n'
            'En el celular (misma empresa tata_stock / código de empresa):\n'
            '• Usuario: ${usuario.usuario}\n'
            '• Clave: la que definiste\n'
            '• Rol: ${RolUtil.etiqueta(rol)}\n\n'
            'No hace falta Google.';
      }
    } else {
      aviso =
          'Usuario creado solo en este dispositivo (nube no disponible). '
          'Activá la sincronización e intentá darlo de alta de nuevo '
          'si debe entrar desde otro equipo.';
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
        'email': nuevo.email,
      }),
    );

    // Aviso interno a administradores / email de la empresa
    try {
      final adminEmail = BrandingService.instance.email.trim();
      await ComunicacionesService.instance.crearNotificacion(
        usuarioDestino: AuthService.instance.currentUser?.usuario ?? 'admin',
        tipo: 'usuario_alta',
        titulo: 'Nuevo usuario: ${nuevo.nombre}',
        cuerpo:
            'Se dio de alta a ${nuevo.usuario}'
            '${UsuarioAuthEmail.esEmailReal(nuevo.email) ? ' (${nuevo.email})' : ''}'
            '${adminEmail.isNotEmpty ? '. Contacto empresa: $adminEmail' : ''}.',
      );
    } catch (e) {
      debugPrint('Notificación alta usuario: $e');
    }

    return (id: id, emailEnviado: emailEnviado, aviso: aviso);
  }

  Future<int> insertar(Usuario usuario) async {
    final r = await insertarConAviso(usuario);
    return r.id;
  }

  Future<int> actualizar(Usuario usuario, {String? nuevaPassword}) async {
    _requiereAdministrador();
    final rol = RolUtil.normalizar(usuario.rol);
    var actualizado = usuario.copyWith(rol: rol);

    if (nuevaPassword != null && nuevaPassword.trim().isNotEmpty) {
      actualizado = actualizado.copyWith(
        password: AuthService.hashPassword(nuevaPassword.trim()),
        debeCambiarPassword: false,
      );
      // La clave la define el admin. No mandamos reset por email porque
      // invalidaría la contraseña recién asignada.
    }

    final resultado = await _repoLocal.actualizar(actualizado);

    if (BackendConfigService.instance.firebaseEnabled &&
        (actualizado.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository().actualizar(actualizado);
      } catch (_) {}
      try {
        await TenantMembershipService.instance.invitarOActualizarMiembro(
          uid: actualizado.firebaseUid!,
          rol: actualizado.rol,
          email: actualizado.email,
          usuario: actualizado.usuario,
          activo: actualizado.activo,
        );
      } catch (e) {
        debugPrint('Membership actualizar usuario: $e');
      }
    }

    await AuthService.instance.registrarCambio(
      'MODIFICAR_USUARIO',
      'usuarios',
      'Modificación de usuario ${actualizado.usuario}',
      valorAnterior:
          jsonEncode({'usuario': usuario.usuario, 'rol': usuario.rol}),
      valorNuevo: jsonEncode(
        {'usuario': actualizado.usuario, 'rol': actualizado.rol},
      ),
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
      try {
        await TenantMembershipService.instance.invitarOActualizarMiembro(
          uid: usuario.firebaseUid!,
          rol: usuario.rol,
          email: usuario.email,
          usuario: usuario.usuario,
          activo: false,
        );
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

  /// Elimina el usuario de este dispositivo y de la nube (Firestore + membership).
  /// No borra la cuenta de Firebase Authentication (hace falta Admin SDK).
  Future<int> eliminar(int id) async {
    _requiereAdministrador();
    final usuarios = await _repoLocal.obtenerTodos();
    final usuario = usuarios.firstWhere((u) => u.id == id);

    if (usuario.id == AuthService.instance.currentUser?.id) {
      throw StateError('No podés eliminar tu propio usuario.');
    }

    final esAdmin = RolUtil.normalizar(usuario.rol) == RolUtil.administrador;
    if (esAdmin) {
      final adminsActivos = usuarios
          .where(
            (u) =>
                u.activo &&
                RolUtil.normalizar(u.rol) == RolUtil.administrador &&
                u.id != id,
          )
          .length;
      if (adminsActivos < 1) {
        throw StateError(
          'No podés eliminar el último administrador activo.',
        );
      }
    }

    final resultado = await _repoLocal.eliminar(id);

    final uid = usuario.firebaseUid;
    if (BackendConfigService.instance.firebaseEnabled &&
        uid != null &&
        uid.isNotEmpty) {
      try {
        await FirestoreUsuarioRepository().eliminarPorUid(uid);
      } catch (e) {
        debugPrint('Firestore eliminar usuario: $e');
      }
      try {
        await TenantMembershipService.instance.eliminarMembresia(uid);
      } catch (e) {
        debugPrint('Membership eliminar usuario: $e');
      }
    }

    await AuthService.instance.registrarCambio(
      'ELIMINAR_USUARIO',
      'usuarios',
      'Eliminación de usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({
        'usuario': usuario.usuario,
        'rol': usuario.rol,
        'email': usuario.email,
      }),
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

    // Email de restablecimiento para alinear también Firebase Auth.
    final email = usuario.email.trim();
    if (FirebaseAuthUsuarioService.instance.disponible &&
        UsuarioAuthEmail.esEmailReal(email)) {
      try {
        await FirebaseAuthUsuarioService.instance.enviarRestablecimiento(
          usuario.usuario,
          email: email,
        );
      } catch (e) {
        debugPrint('Email restablecer password: $e');
      }
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
