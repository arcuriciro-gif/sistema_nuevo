import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../core/security/authorization_service.dart';
import '../database/database_helper.dart';

/// Resultado de validación / dry-run de un archivo de backup.
class BackupValidation {
  BackupValidation({
    required this.ok,
    required this.path,
    required this.sha256,
    required this.sizeBytes,
    this.message,
  });

  final bool ok;
  final String path;
  final String sha256;
  final int sizeBytes;
  final String? message;
}

/// Backup / restore certificable (Capacidad 5).
class BackupService {
  static const keepAutoBackups = 7;

  Future<String> sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Abre el archivo en modo lectura y exige `PRAGMA integrity_check = ok`.
  Future<BackupValidation> validarArchivo(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return BackupValidation(
        ok: false,
        path: path,
        sha256: '',
        sizeBytes: 0,
        message: 'Archivo no encontrado',
      );
    }
    final size = await file.length();
    final digest = await sha256OfFile(path);
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final rows = await db.rawQuery('PRAGMA integrity_check');
      final result = rows.isEmpty ? '' : rows.first.values.first?.toString();
      final ok = result?.toLowerCase() == 'ok';
      return BackupValidation(
        ok: ok,
        path: path,
        sha256: digest,
        sizeBytes: size,
        message: ok ? null : 'integrity_check: $result',
      );
    } catch (e) {
      return BackupValidation(
        ok: false,
        path: path,
        sha256: digest,
        sizeBytes: size,
        message: 'No se pudo abrir backup: $e',
      );
    } finally {
      if (db != null && db.isOpen) {
        await db.close();
      }
    }
  }

  Future<String> exportarBackup() async {
    AuthorizationService.instance.require(
      AuthModules.backup,
      AuthzAction.editar,
      operacion: 'exportar backup',
    );
    final origen = File(await DatabaseHelper.instance.dbFilePath);
    if (!await origen.exists()) {
      throw Exception('Base de datos no encontrada');
    }

    final docs = await getApplicationDocumentsDirectory();
    final fecha = DateTime.now();
    final stamp =
        '${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}_'
        '${fecha.hour.toString().padLeft(2, '0')}${fecha.minute.toString().padLeft(2, '0')}${fecha.second.toString().padLeft(2, '0')}';
    final nombre = 'eltata_backup_$stamp.db';
    final destino = File(p.join(docs.path, nombre));
    await origen.copy(destino.path);

    final validation = await validarArchivo(destino.path);
    if (!validation.ok) {
      try {
        await destino.delete();
      } catch (_) {}
      throw StateError(
        'Backup inválido tras copiar: ${validation.message ?? 'integrity fail'}',
      );
    }
    await File('${destino.path}.sha256').writeAsString(
      '${validation.sha256}  ${p.basename(destino.path)}\n',
    );
    await podarBackupsAntiguos(docs.path);
    return destino.path;
  }

  /// Conserva los [keepAutoBackups] backups más recientes en [dir].
  Future<int> podarBackupsAntiguos(String dir, {int keep = keepAutoBackups}) async {
    final folder = Directory(dir);
    if (!await folder.exists()) return 0;
    final files = await folder
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith('eltata_backup_') && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    var removed = 0;
    for (var i = keep; i < files.length; i++) {
      try {
        await files[i].delete();
        final side = File('${files[i].path}.sha256');
        if (await side.exists()) await side.delete();
        removed++;
      } catch (e) {
        debugPrint('Backup prune: $e');
      }
    }
    return removed;
  }

  Future<void> compartirBackup() async {
    final path = await exportarBackup();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Backup EL TATA Manager',
      ),
    );
  }

  Future<bool> restaurarBackup() async {
    AuthorizationService.instance.requireAdmin(operacion: 'restaurar backup');
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return false;
    }
    await restaurarDesdeArchivo(result.files.first.path!);
    return true;
  }

  /// Restore atómico: validar → copiar a `.restore_tmp` → validar tmp →
  /// cerrar DB viva → renombrar viva a `.pre_restore` → promover tmp.
  Future<void> restaurarDesdeArchivo(String origenPath) async {
    AuthorizationService.instance.requireAdmin(operacion: 'restaurar backup');

    final validation = await validarArchivo(origenPath);
    if (!validation.ok) {
      throw StateError(
        'Backup rechazado (dry-run): ${validation.message ?? 'inválido'}',
      );
    }

    final destinoPath = await DatabaseHelper.instance.dbFilePath;
    final destino = File(destinoPath);
    final parent = destino.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final tmpPath = '$destinoPath.restore_tmp';
    final tmp = File(tmpPath);
    if (await tmp.exists()) await tmp.delete();
    await File(origenPath).copy(tmpPath);

    final tmpValidation = await validarArchivo(tmpPath);
    if (!tmpValidation.ok) {
      try {
        await tmp.delete();
      } catch (_) {}
      throw StateError(
        'Copia temporal inválida: ${tmpValidation.message ?? 'integrity fail'}',
      );
    }

    await DatabaseHelper.instance.cerrar();

    final preRestore = File('$destinoPath.pre_restore');
    if (await preRestore.exists()) {
      await preRestore.delete();
    }
    if (await destino.exists()) {
      await destino.rename(preRestore.path);
    }
    await tmp.rename(destinoPath);

    // Registrar metadatos de restore para panel técnico.
    try {
      final meta = {
        'restoredAt': DateTime.now().toUtc().toIso8601String(),
        'sourceSha256': validation.sha256,
        'sourcePath': origenPath,
        'sizeBytes': validation.sizeBytes,
      };
      await File('$destinoPath.restore_meta.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
    } catch (e) {
      debugPrint('restore meta: $e');
    }
  }
}
