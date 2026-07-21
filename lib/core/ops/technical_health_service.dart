import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../database/database_helper.dart';
import '../../services/auto_backup_service.dart';
import '../config/backend_config_service.dart';
import '../sync/sync_health.dart';

/// Versiones de contrato de plataforma (Capacidad 5 / ADR §9).
class PlatformVersions {
  static const domain = '3';
  static const sync = '2';
  static const events = '1';
  static int get schema => DatabaseHelper.schemaVersion;
}

/// Snapshot agregado para el panel técnico (admin).
class TechnicalHealthSnapshot {
  TechnicalHealthSnapshot({
    required this.appName,
    required this.appVersion,
    required this.buildNumber,
    required this.schemaVersion,
    required this.domainVersion,
    required this.syncVersion,
    required this.eventsVersion,
    required this.tenantId,
    required this.dbPath,
    required this.sync,
    required this.lastAutoBackup,
    required this.lastRestoreAt,
    required this.platform,
  });

  final String appName;
  final String appVersion;
  final String buildNumber;
  final int schemaVersion;
  final String domainVersion;
  final String syncVersion;
  final String eventsVersion;
  final String tenantId;
  final String dbPath;
  final SyncHealthSnapshot sync;
  final DateTime? lastAutoBackup;
  final DateTime? lastRestoreAt;
  final String platform;
}

class TechnicalHealthService {
  TechnicalHealthService._();
  static final TechnicalHealthService instance = TechnicalHealthService._();

  Future<TechnicalHealthSnapshot> snapshot() async {
    final info = await PackageInfo.fromPlatform();
    final sync = await SyncHealthService.instance.snapshot();
    final dbPath = await DatabaseHelper.instance.dbFilePath;
    DateTime? lastRestore;
    try {
      final meta = File('$dbPath.restore_meta.json');
      if (await meta.exists()) {
        final text = await meta.readAsString();
        final match = RegExp(r'"restoredAt"\s*:\s*"([^"]+)"').firstMatch(text);
        if (match != null) {
          lastRestore = DateTime.tryParse(match.group(1)!);
        }
      }
    } catch (e) {
      debugPrint('restore meta read: $e');
    }

    return TechnicalHealthSnapshot(
      appName: info.appName,
      appVersion: info.version,
      buildNumber: info.buildNumber,
      schemaVersion: PlatformVersions.schema,
      domainVersion: PlatformVersions.domain,
      syncVersion: PlatformVersions.sync,
      eventsVersion: PlatformVersions.events,
      tenantId: BackendConfigService.instance.tenantId,
      dbPath: dbPath,
      sync: sync,
      lastAutoBackup: await AutoBackupService.instance.ultimoBackup,
      lastRestoreAt: lastRestore,
      platform: _platformLabel(),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
