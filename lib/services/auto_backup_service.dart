import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

/// Manages periodic automatic backups.
/// Call [iniciar] once at app startup (after login) to activate.
/// Respects the user-configured interval and can be disabled.
class AutoBackupService {
  AutoBackupService._();
  static final AutoBackupService instance = AutoBackupService._();

  static const _keyEnabled = 'auto_backup_enabled';
  static const _keyIntervalHoras = 'auto_backup_interval_horas';
  static const _keyUltimoBackup = 'auto_backup_ultimo';

  Timer? _timer;
  final BackupService _backupSvc = BackupService();

  // ── Preferencias ──────────────────────────────────────────────────────────

  Future<bool> get habilitado async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  Future<int> get intervaloHoras async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyIntervalHoras) ?? 24;
  }

  Future<DateTime?> get ultimoBackup async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyUltimoBackup);
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<void> setHabilitado(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (value) {
      await iniciar();
    } else {
      detener();
    }
  }

  Future<void> setIntervaloHoras(int horas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntervalHoras, horas);
    // Restart timer with new interval
    if (await habilitado) {
      detener();
      await iniciar();
    }
  }

  // ── Control ───────────────────────────────────────────────────────────────

  /// Start or restart the periodic timer based on saved preferences.
  Future<void> iniciar() async {
    detener();
    if (!await habilitado) return;

    final horas = await intervaloHoras;
    final interval = Duration(hours: horas);

    // Check immediately if a backup is overdue
    await _verificarYHacerBackup();

    _timer = Timer.periodic(interval, (_) async {
      await _verificarYHacerBackup();
    });
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Lógica interna ────────────────────────────────────────────────────────

  Future<void> _verificarYHacerBackup() async {
    try {
      final horas = await intervaloHoras;
      final ultimo = await ultimoBackup;
      final ahora = DateTime.now();

      if (ultimo != null &&
          ahora.difference(ultimo).inHours < horas) {
        return; // Not yet due
      }

      await _backupSvc.exportarBackup();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUltimoBackup, ahora.toIso8601String());
    } catch (_) {
      // Silent: auto-backup failures should not interrupt the user
    }
  }

  /// Force an immediate backup and update the last-backup timestamp.
  Future<String> ejecutarAhora() async {
    final path = await _backupSvc.exportarBackup();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyUltimoBackup,
      DateTime.now().toIso8601String(),
    );
    return path;
  }
}
