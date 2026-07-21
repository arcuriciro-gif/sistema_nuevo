import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import 'platform_capabilities.dart';

/// Configuración del backend (SQLite local o Firebase en tiempo real).
class BackendConfigService {
  BackendConfigService._();

  static final BackendConfigService instance = BackendConfigService._();

  static const _firebaseEnabledKey = 'backend_firebase_enabled';
  static const _tenantIdKey = 'backend_tenant_id';

  /// Solo legado / migración explícita. No usar como default de instalaciones nuevas.
  static const legacySharedTenantId = 'tata_stock';

  bool _firebaseEnabled = false;
  String _tenantId = '';

  bool get firebaseEnabled => _firebaseEnabled;
  String get tenantId => _tenantId;

  bool get isLegacySharedTenant => _tenantId == legacySharedTenantId;

  /// Genera un tenantId no adivinable para una empresa nueva.
  static String generarTenantIdNuevo() {
    final raw = const Uuid().v4().replaceAll('-', '');
    return 't_$raw';
  }

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

    final existing = prefs.getString(_tenantIdKey)?.trim() ?? '';
    if (existing.isNotEmpty) {
      _tenantId = existing;
    } else {
      // Instalación nueva: tenant propio (no compartir tata_stock).
      _tenantId = generarTenantIdNuevo();
      await prefs.setString(_tenantIdKey, _tenantId);
      debugPrint('BackendConfig: tenant nuevo asignado $_tenantId');
    }

    debugPrint(
      'BackendConfig firebaseEnabled=$_firebaseEnabled tenant=$_tenantId',
    );
  }

  Future<void> setFirebaseEnabled(bool value) async {
    _firebaseEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firebaseEnabledKey, value);
  }

  /// Asigna tenant explícitamente (onboarding / migración).
  /// Vacío no está permitido (evita caer en tenant compartido).
  Future<void> setTenantId(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('tenantId no puede ser vacío');
    }
    _tenantId = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantIdKey, normalized);
  }
}
