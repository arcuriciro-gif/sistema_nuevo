import '../config/backend_config_service.dart';

class UsuarioAuthEmail {
  static String paraUsuario(String usuario) {
    final tenant = BackendConfigService.instance.tenantId;
    final user = usuario.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return '$user@$tenant.tatastock.app';
  }
}
