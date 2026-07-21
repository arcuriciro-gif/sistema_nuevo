import '../auth/rol_util.dart';
import '../../services/auth_service.dart';
import '../../services/permisos_service.dart';

/// Acciones de autorización (Capacidad 1 — niveles 2/3).
enum AuthzAction { ver, crear, editar, eliminar, anular, administrar }

/// Guardas de autorización en casos de uso / servicios.
/// Nivel 4 (Firestore Rules) es independiente y obligatorio.
class AuthorizationService {
  AuthorizationService._();

  static final AuthorizationService instance = AuthorizationService._();

  String? get _rol => AuthService.instance.currentUser?.rol;

  bool get esAdministrador => RolUtil.esAdministrador(_rol);

  bool puede(String modulo, AuthzAction action) {
    final rol = _rol;
    if (rol == null || rol.trim().isEmpty) return false;
    if (RolUtil.esAdministrador(rol)) return true;
    if (RolUtil.normalizar(rol) == 'solo_lectura') {
      return action == AuthzAction.ver;
    }
    final perms = PermisosService.instance;
    switch (action) {
      case AuthzAction.ver:
        return perms.puedeVer(rol, modulo);
      case AuthzAction.crear:
        return perms.puedeCrear(rol, modulo);
      case AuthzAction.editar:
        return perms.puedeEditar(rol, modulo);
      case AuthzAction.eliminar:
      case AuthzAction.anular:
        return perms.puedeEliminar(rol, modulo);
      case AuthzAction.administrar:
        return false;
    }
  }

  void require(String modulo, AuthzAction action, {String? operacion}) {
    if (puede(modulo, action)) return;
    final op = operacion ?? '${action.name}:$modulo';
    throw StateError('No autorizado: $op');
  }

  void requireAdmin({String operacion = 'operación de administrador'}) {
    if (esAdministrador) return;
    throw StateError('Solo el administrador puede: $operacion');
  }
}
