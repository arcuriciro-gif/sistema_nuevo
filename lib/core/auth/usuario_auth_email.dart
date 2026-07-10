import '../config/backend_config_service.dart';

class UsuarioAuthEmail {
  /// Email real si es válido; si no, email sintético para Firebase Auth.
  static String paraUsuario(String usuario, {String? emailReal}) {
    final real = (emailReal ?? '').trim();
    if (_esEmailReal(real)) return real.toLowerCase();
    return sintetico(usuario);
  }

  static bool _esEmailReal(String email) {
    if (!email.contains('@') || email.length < 5) return false;
    if (email.toLowerCase().endsWith('.tatastock.app')) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  static bool esEmailReal(String? email) => _esEmailReal((email ?? '').trim());

  /// Firebase Auth exige un email válido.
  /// El tenant puede tener `_` (ej. tata_stock); en el dominio eso es inválido.
  static String sintetico(String usuario) {
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
