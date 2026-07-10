import '../config/backend_config_service.dart';

class UsuarioAuthEmail {
  /// Firebase Auth exige un email válido.
  /// El tenant puede tener `_` (ej. tata_stock); en el dominio eso es inválido.
  static String paraUsuario(String usuario) {
    final tenant = BackendConfigService.instance.tenantId
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final user = usuario
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final safeUser = user.isEmpty ? 'user' : user;
    final safeTenant = tenant.isEmpty ? 'default' : tenant;
    return '$safeUser@$safeTenant.tatastock.app';
  }
}
