import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import 'platform_capabilities.dart';

/// Configuración del backend (SQLite local o Firebase en tiempo real).
class BackendConfigService {
  BackendConfigService._();

  static final BackendConfigService instance = BackendConfigService._();

  static const _firebaseEnabledKey = 'backend_firebase_enabled';
  static const _tenantIdKey = 'backend_tenant_id';
  static const _defaultTenant = 'tata_stock';

  bool _firebaseEnabled = false;
  String _tenantId = _defaultTenant;

  bool get firebaseEnabled => _firebaseEnabled;
  String get tenantId => _tenantId;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_firebaseEnabledKey);
    // En Windows la nube es opt-in (evita crash al primer login).
    // En Android/otras, si hay Firebase configurado, queda activo por defecto.
    if (stored != null) {
      _firebaseEnabled = stored;
    } else if (PlatformCapabilities.isWindowsDesktop) {
      _firebaseEnabled = false;
    } else {
      _firebaseEnabled = DefaultFirebaseOptions.isConfigured;
    }
    _tenantId = prefs.getString(_tenantIdKey) ?? _defaultTenant;
    debugPrint(
      'BackendConfig firebaseEnabled=$_firebaseEnabled tenant=$_tenantId',
    );
  }

  Future<void> setFirebaseEnabled(bool value) async {
    _firebaseEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firebaseEnabledKey, value);
  }

  Future<void> setTenantId(String value) async {
    final normalized = value.trim().isEmpty ? _defaultTenant : value.trim();
    _tenantId = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantIdKey, normalized);
  }
}
