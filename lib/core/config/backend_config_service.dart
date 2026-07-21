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
  static const _empresaConfirmadaKey = 'backend_empresa_confirmada';

  /// Solo legado / migración explícita. No usar como default de instalaciones nuevas.
  static const legacySharedTenantId = 'tata_stock';

  bool _firebaseEnabled = false;
  String _tenantId = '';
  bool _empresaConfirmada = false;

  bool get firebaseEnabled => _firebaseEnabled;
  String get tenantId => _tenantId;

  /// true cuando el admin eligió/confirmó el código (no el UUID automático).
  bool get empresaConfirmada => _empresaConfirmada;

  bool get isLegacySharedTenant => _tenantId == legacySharedTenantId;

  /// Tenant generado solo por instalar la app (`t_<hex>`).
  static bool esTenantAutogenerado(String id) {
    return RegExp(r'^t_[a-f0-9]{16,}$').hasMatch(id.trim().toLowerCase());
  }

  bool get esEmpresaAutogenerada => esTenantAutogenerado(_tenantId);

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
      await prefs.setBool(_empresaConfirmadaKey, false);
      _empresaConfirmada = false;
      debugPrint('BackendConfig: tenant nuevo asignado $_tenantId');
    }

    if (prefs.containsKey(_empresaConfirmadaKey)) {
      _empresaConfirmada = prefs.getBool(_empresaConfirmadaKey) ?? false;
    } else {
      // Migración: códigos legados / manuales ya son empresa real.
      _empresaConfirmada = !esTenantAutogenerado(_tenantId);
      await prefs.setBool(_empresaConfirmadaKey, _empresaConfirmada);
    }

    debugPrint(
      'BackendConfig firebaseEnabled=$_firebaseEnabled tenant=$_tenantId '
      'empresaConfirmada=$_empresaConfirmada',
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
    _empresaConfirmada = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantIdKey, normalized);
    await prefs.setBool(_empresaConfirmadaKey, true);
  }

  /// Confirma la empresa actual (p. ej. una instalación nueva a propósito).
  Future<void> confirmarEmpresaActual() async {
    _empresaConfirmada = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_empresaConfirmadaKey, true);
  }
}
