import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Política de acceso del admin por defecto (Fase 1).
///
/// - Primera instalación: `admin` / `admin123` sigue funcionando UNA vez,
///   con `debeCambiarPassword = true`.
/// - Tras cambiar la clave: se desactiva el backdoor `admin123`.
/// - Alternativa: código de recuperación local (mostrado al admin).
class AdminAccessPolicy {
  AdminAccessPolicy._();

  static final AdminAccessPolicy instance = AdminAccessPolicy._();

  static const hashAdmin123 =
      '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9';

  static const _kDefaultRecoveryEnabled = 'admin_default_recovery_enabled';
  static const _kRecoveryHash = 'admin_recovery_code_hash';
  static const _kRecoveryCreated = 'admin_recovery_code_created_at';
  static const _kPlainShownOnce = 'admin_recovery_code_plain_once';

  Future<bool> isDefaultRecoveryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Default true: instalaciones existentes / primera vez.
    return prefs.getBool(_kDefaultRecoveryEnabled) ?? true;
  }

  Future<void> disableDefaultRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDefaultRecoveryEnabled, false);
  }

  /// Genera código si no existe. Devuelve el plain solo la primera vez
  /// (queda en prefs temporalmente para mostrarlo en UI).
  Future<String?> ensureRecoveryCode({bool forceNew = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final existingHash = prefs.getString(_kRecoveryHash);
    if (existingHash != null && existingHash.isNotEmpty && !forceNew) {
      return prefs.getString(_kPlainShownOnce);
    }

    final plain = _generateCode();
    await prefs.setString(_kRecoveryHash, _hash(plain));
    await prefs.setString(
      _kRecoveryCreated,
      DateTime.now().toUtc().toIso8601String(),
    );
    await prefs.setString(_kPlainShownOnce, plain);
    return plain;
  }

  Future<String?> peekRecoveryCodePlain() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPlainShownOnce);
  }

  Future<void> clearRecoveryCodePlain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPlainShownOnce);
  }

  Future<bool> validateRecoveryCode(String input) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kRecoveryHash);
    if (stored == null || stored.isEmpty) return false;
    return stored == _hash(input.trim().toUpperCase());
  }

  /// Tras recovery exitoso: regenera código y deja plain para mostrar.
  Future<String> rotateRecoveryCode() async {
    final plain = await ensureRecoveryCode(forceNew: true);
    return plain ?? '';
  }

  String _generateCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final chars = List.generate(8, (_) => alphabet[rnd.nextInt(alphabet.length)]);
    return chars.join();
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode(value.trim().toUpperCase())).toString();
  }
}
