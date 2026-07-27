import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

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
    // Hardening: default OFF. Solo bootstrap explícito lo habilita.
    return prefs.getBool(_kDefaultRecoveryEnabled) ?? false;
  }

  /// Marca explícitamente el bootstrap local (seed admin). Idempotente.
  Future<void> enableDefaultRecoveryForBootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDefaultRecoveryEnabled, true);
  }

  /// Migración one-shot: instalaciones que ya cambiaron la clave admin
  /// dejan de tener recovery; las que siguen en hash bootstrap lo conservan.
  Future<void> migrateHardeningRecoveryDefault(DatabaseExecutor db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_kDefaultRecoveryEnabled)) return;
    final admin = await db.query(
      'usuarios',
      columns: ['password'],
      where: "LOWER(usuario) = 'admin'",
      limit: 1,
    );
    if (admin.isEmpty) {
      await prefs.setBool(_kDefaultRecoveryEnabled, false);
      return;
    }
    final hash = admin.first['password']?.toString() ?? '';
    final stillBootstrap = hash == hashAdmin123;
    await prefs.setBool(_kDefaultRecoveryEnabled, stillBootstrap);
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
