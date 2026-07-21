/// Normalización y utilidades de roles del sistema.
class RolUtil {
  static const administrador = 'admin';
  static const encargado = 'encargado';
  static const empleado = 'empleado';

  /// Roles visibles al crear/editar usuarios.
  static const rolesAsignables = [
    administrador,
    encargado,
    empleado,
    'solo_lectura',
  ];

  static String normalizar(String rol) {
    final valor = rol.trim().toLowerCase();
    switch (valor) {
      case 'administrador':
      case 'admin':
        return administrador;
      case 'supervisor':
      case 'encargado':
        return encargado;
      case 'usuario':
        return empleado;
      default:
        return valor;
    }
  }

  static String etiqueta(String rol) {
    switch (normalizar(rol)) {
      case administrador:
        return 'Administrador';
      case encargado:
        return 'Encargado';
      case empleado:
        return 'Empleado';
      case 'solo_lectura':
        return 'Solo lectura';
      default:
        return rol;
    }
  }

  static bool esAdministrador(String? rol) =>
      normalizar(rol ?? '') == administrador;

  /// Clave de permisos en SQLite (encargado usa matriz de supervisor).
  static String clavePermisos(String rol) {
    final normalizado = normalizar(rol);
    if (normalizado == encargado) return 'supervisor';
    return normalizado;
  }
}
