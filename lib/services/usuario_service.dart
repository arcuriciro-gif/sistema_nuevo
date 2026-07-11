import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/auth/rol_util.dart';
import '../core/auth/usuario_auth_email.dart';
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
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
    Usuario usuario,
  ) async {
    _requiereAdministrador();
    final ahora = DateTime.now();
    final rol = RolUtil.normalizar(usuario.rol);
    final passwordPlano = usuario.password;
    final emailReal = usuario.email.trim();
    var nuevo = usuario.copyWith(
      rol: rol,
      // Contacto opcional; Auth usa siempre email sintético del usuario.
      email: emailReal,
      fechaCreacion: usuario.fechaCreacion ?? ahora,
      password: AuthService.hashPassword(passwordPlano),
      // La clave la define el admin: no forzar cambio al primer login.
      debeCambiarPassword: false,
    );

    final firebase = FirebaseAuthUsuarioService.instance;
    var emailEnviado = false;
    String? aviso;
    if (firebase.disponible) {
      try {
        final uid = await firebase.asegurarCuenta(
          usuario.usuario,
          passwordPlano,
        );
        nuevo = nuevo.copyWith(firebaseUid: uid);
        await FirestoreUsuarioRepository().insertar(nuevo);
        aviso =
            'Usuario "${usuario.usuario}" creado.\n'
            'Entrar con ese usuario y la clave que le asignaste '
            '(no uses el email para iniciar sesión).';
      } catch (e) {
        // Igual dejamos el usuario local para que pueda entrar en esta PC.
        debugPrint('Firebase alta usuario: $e');
        aviso =
            'Usuario creado en esta PC, pero la nube falló:\n$e\n\n'
            'Podés entrar acá con usuario/clave. '
            'Para el celular: Restablecer contraseña o limpiar Auth en Firebase.';
      }
    } else {
      aviso =
          'Usuario creado solo en este dispositivo (Firebase no disponible).';
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
    final actuales = await _repoLocal.obtenerTodos();
    final anterior = actuales.cast<Usuario?>().firstWhere(
          (u) => u?.id == usuario.id,
          orElse: () => null,
        );

    if (anterior != null &&
        RolUtil.esAdministrador(anterior.rol) &&
        !RolUtil.esAdministrador(rol)) {
      final otrosAdmins = actuales
          .where(
            (u) =>
                u.id != usuario.id &&
                u.activo &&
                RolUtil.esAdministrador(u.rol),
          )
          .length;
      if (otrosAdmins == 0) {
        throw StateError(
          'No podés quitar el rol administrador del único admin activo.',
        );
      }
    }

    if (usuario.id == AuthService.instance.currentUser?.id &&
        !RolUtil.esAdministrador(rol)) {
      throw StateError('No podés quitarte el rol de administrador.');
    }

    var actualizado = usuario.copyWith(rol: rol);
    final cambiaPassword =
        nuevaPassword != null && nuevaPassword.trim().isNotEmpty;

    if (cambiaPassword) {
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
      valorAnterior: jsonEncode({
        'usuario': anterior?.usuario ?? usuario.usuario,
        'rol': anterior?.rol ?? usuario.rol,
        'activo': anterior?.activo ?? usuario.activo,
        'nombre': anterior?.nombre ?? usuario.nombre,
      }),
      valorNuevo: jsonEncode({
        'usuario': actualizado.usuario,
        'rol': actualizado.rol,
        'activo': actualizado.activo,
        'nombre': actualizado.nombre,
        if (cambiaPassword) 'passwordRestablecida': true,
      }),
    );

    if (cambiaPassword) {
      await AuthService.instance.registrarCambio(
        'RESTABLECER_PASSWORD',
        'usuarios',
        'Contraseña cambiada al editar usuario ${actualizado.usuario}',
        valorNuevo: jsonEncode({
          'usuario': actualizado.usuario,
          'fecha': DateTime.now().toIso8601String(),
        }),
      );
    }

    return resultado;
  }

  Future<int> activar(int id) async {
    _requiereAdministrador();
    final usuarios = await _repoLocal.obtenerTodos();
    final usuario = usuarios.firstWhere((u) => u.id == id);
    final resultado =
        await _repoLocal.actualizar(usuario.copyWith(activo: true));

    if (BackendConfigService.instance.firebaseEnabled &&
        (usuario.firebaseUid?.isNotEmpty ?? false)) {
      try {
        await FirestoreUsuarioRepository()
            .actualizar(usuario.copyWith(activo: true));
      } catch (_) {}
    }

    await AuthService.instance.registrarCambio(
      'ACTIVAR_USUARIO',
      'usuarios',
      'Reactivación de usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({'activo': false}),
      valorNuevo: jsonEncode({'activo': true}),
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

    if (RolUtil.esAdministrador(usuario.rol)) {
      final otrosAdmins = usuarios
          .where(
            (u) =>
                u.id != id && u.activo && RolUtil.esAdministrador(u.rol),
          )
          .length;
      if (otrosAdmins == 0) {
        throw StateError('No podés desactivar el único administrador activo.');
      }
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

  /// Elimina el usuario de SQLite y de Firestore. No borra la cuenta de
  /// Firebase Authentication (hace falta consola o Admin SDK).
  Future<void> eliminar(int id) async {
    _requiereAdministrador();
    final usuarios = await _repoLocal.obtenerTodos();
    final usuario = usuarios.firstWhere((u) => u.id == id);

    if (usuario.id == AuthService.instance.currentUser?.id) {
      throw StateError('No podés eliminar tu propio usuario.');
    }

    if (RolUtil.esAdministrador(usuario.rol)) {
      final otrosAdmins = usuarios
          .where(
            (u) =>
                u.id != id && u.activo && RolUtil.esAdministrador(u.rol),
          )
          .length;
      if (otrosAdmins == 0) {
        throw StateError('No podés eliminar el único administrador activo.');
      }
    }

    var uid = usuario.firebaseUid;
    if ((uid == null || uid.isEmpty) &&
        BackendConfigService.instance.firebaseEnabled) {
      try {
        final remoto =
            await FirestoreUsuarioRepository().buscarPorUsuario(usuario.usuario);
        uid = remoto?.firebaseUid;
      } catch (_) {}
    }

    await _repoLocal.eliminar(id);

    if (BackendConfigService.instance.firebaseEnabled &&
        uid != null &&
        uid.isNotEmpty) {
      try {
        await FirestoreUsuarioRepository().eliminarPorUid(uid);
      } catch (e) {
        debugPrint('Eliminar usuario Firestore: $e');
      }
    }

    await AuthService.instance.registrarCambio(
      'ELIMINAR_USUARIO',
      'usuarios',
      'Eliminación de usuario ${usuario.usuario}',
      valorAnterior: jsonEncode({
        'usuario': usuario.usuario,
        'rol': usuario.rol,
        'nombre': usuario.nombre,
        'email': usuario.email,
        'activo': usuario.activo,
      }),
    );
  }

  /// Restablece contraseña local y alinea la cuenta de Firebase Auth.
  Future<String?> restablecerPassword(
    Usuario usuario,
    String nuevaPassword,
  ) async {
    _requiereAdministrador();
    if (nuevaPassword.trim().length < 6) {
      throw StateError(
        'La contraseña debe tener al menos 6 caracteres (requisito de Firebase).',
      );
    }

    final clave = nuevaPassword.trim();
    var actualizado = usuario.copyWith(
      password: AuthService.hashPassword(clave),
      debeCambiarPassword: false,
    );
    await _repoLocal.actualizar(actualizado);

    String? aviso =
        'Listo. Entrá con usuario "${usuario.usuario}" y la clave nueva.';

    if (BackendConfigService.instance.firebaseEnabled) {
      try {
        if (FirebaseAuthUsuarioService.instance.disponible) {
          final uid = await FirebaseAuthUsuarioService.instance.asegurarCuenta(
            usuario.usuario,
            clave,
          );
          actualizado = actualizado.copyWith(firebaseUid: uid);
          await _repoLocal.actualizar(actualizado);
        }
        if (actualizado.firebaseUid?.isNotEmpty ?? false) {
          await FirestoreUsuarioRepository().actualizar(actualizado);
        }
        aviso =
            'Clave actualizada en esta PC y en la nube.\n'
            'Usuario: ${usuario.usuario}\n'
            'Usá esa misma clave en el celular.';
      } catch (e) {
        debugPrint('Restablecer + Auth: $e');
        aviso =
            'Clave local OK, pero la nube falló:\n$e\n\n'
            'En Firebase Console → Authentication → Users, '
            'eliminá ${FirebaseAuthUsuarioService.instance.authEmailPara(usuario.usuario)} '
            'y volvé a Restablecer.';
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

    return aviso;
  }

  Future<bool> existeUsuario(String usuario) async {
    _requiereAdministrador();
    return _repoLocal.existeUsuario(usuario);
  }
}
