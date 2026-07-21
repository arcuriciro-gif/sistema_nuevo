import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/ops/technical_health_service.dart';
import 'package:sistema_nuevo/core/security/authorization_service.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 5 — contratos release', () {
    test('versiones de plataforma son estables', () {
      expect(PlatformVersions.schema, DatabaseHelper.schemaVersion);
      expect(PlatformVersions.domain, isNotEmpty);
      expect(PlatformVersions.sync, isNotEmpty);
      expect(PlatformVersions.events, isNotEmpty);
    });
  });

  group('Capacidad 5 — backup / integrity', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('c5_backup_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'live.db'),
      );
      AuthService.instance.currentUser = Usuario(
        nombre: 'Admin',
        usuario: 'admin',
        password: 'x',
        rol: 'admin',
      );
    });

    tearDown(() async {
      AuthService.instance.currentUser = null;
      try {
        await DatabaseHelper.instance.resetForTests(
          absolutePath: p.join(tmp.path, 'closed.db'),
        );
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('validarArchivo ok en DB sana', () async {
      // Abre/crea DB viva
      final db = await DatabaseHelper.instance.database;
      await db.execute(
        'CREATE TABLE IF NOT EXISTS _c5_probe(id INTEGER PRIMARY KEY)',
      );
      final path = await DatabaseHelper.instance.dbFilePath;
      final v = await BackupService().validarArchivo(path);
      expect(v.ok, isTrue);
      expect(v.sha256, isNotEmpty);
      expect(v.sizeBytes, greaterThan(0));
    });

    test('validarArchivo falla con basura', () async {
      final bad = File(p.join(tmp.path, 'basura.db'));
      await bad.writeAsString('esto no es sqlite');
      final v = await BackupService().validarArchivo(bad.path);
      expect(v.ok, isFalse);
    });

    test('restore atómico rechaza backup inválido y no borra vivo', () async {
      final live = await DatabaseHelper.instance.dbFilePath;
      final db = await DatabaseHelper.instance.database;
      await db.execute(
        'CREATE TABLE IF NOT EXISTS _c5_marker(v INTEGER)',
      );
      await db.insert('_c5_marker', {'v': 1});

      final bad = File(p.join(tmp.path, 'malo.db'));
      await bad.writeAsString('no-db');

      expect(
        () => BackupService().restaurarDesdeArchivo(bad.path),
        throwsA(isA<StateError>()),
      );

      expect(await File(live).exists(), isTrue);
      final still = await DatabaseHelper.instance.database;
      final rows = await still.query('_c5_marker');
      expect(rows, isNotEmpty);
    });

    test('restore atómico desde backup válido', () async {
      final livePath = await DatabaseHelper.instance.dbFilePath;
      final liveDb = await DatabaseHelper.instance.database;
      await liveDb.execute(
        'CREATE TABLE IF NOT EXISTS _c5_live(id INTEGER PRIMARY KEY, n TEXT)',
      );
      await liveDb.insert('_c5_live', {'n': 'antes'});

      // Crear backup válido separado
      final backupPath = p.join(tmp.path, 'good_backup.db');
      await File(livePath).copy(backupPath);
      // Mutar live después del backup
      await liveDb.insert('_c5_live', {'n': 'despues'});

      final svc = BackupService();
      final validation = await svc.validarArchivo(backupPath);
      expect(validation.ok, isTrue);

      await svc.restaurarDesdeArchivo(backupPath);

      // Reabrir
      final reopened = await DatabaseHelper.instance.database;
      final rows = await reopened.query('_c5_live');
      expect(rows.length, 1);
      expect(rows.first['n'], 'antes');
      expect(await File('$livePath.pre_restore').exists(), isTrue);
    });

    test('podarBackupsAntiguos conserva N', () async {
      final dir = p.join(tmp.path, 'backs');
      await Directory(dir).create();
      for (var i = 0; i < 10; i++) {
        await File(p.join(dir, 'eltata_backup_2026010$i.db'))
            .writeAsString('x$i');
      }
      final removed = await BackupService().podarBackupsAntiguos(dir, keep: 3);
      expect(removed, 7);
      final left = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .length;
      expect(left, 3);
    });

    test('solo_lectura no exporta backup', () async {
      AuthService.instance.currentUser = Usuario(
        nombre: 'RO',
        usuario: 'ro',
        password: 'x',
        rol: 'solo_lectura',
      );
      expect(
        () => BackupService().exportarBackup(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
