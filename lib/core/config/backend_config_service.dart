import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';

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
    _firebaseEnabled = stored ?? DefaultFirebaseOptions.isConfigured;
    _tenantId = prefs.getString(_tenantIdKey) ?? _defaultTenant;
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
