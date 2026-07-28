import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/observability/sync_circuit_breaker.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Campo notebook 2026-07-28: sync fallaba
/// `UPDATE proveedores SET actualizadoEn = ?` → no such column
/// → circuit_open → 99 pendientes trabados.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('prov_act_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 't.db'),
    );
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrar();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('fresh DB: proveedores tiene actualizadoEn (onCreate)', () async {
    final db = await DatabaseHelper.instance.database;
    final info = await db.rawQuery('PRAGMA table_info(proveedores)');
    final cols = info.map((r) => r['name']?.toString()).toSet();
    expect(cols.contains('actualizadoEn'), isTrue);
    expect(DatabaseHelper.schemaVersion, greaterThanOrEqualTo(39));
  });

  test('UPDATE proveedores.actualizadoEn no lanza', () async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('proveedores', {
      'nombre': 'Prov Test',
      'fechaCreacion': DateTime.now().toUtc().toIso8601String(),
    });
    await db.update(
      'proveedores',
      {'actualizadoEn': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    final row = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(row.first['actualizadoEn'], isNotEmpty);
  });

  test('forceClose cierra circuit_open', () {
    final cb = SyncCircuitBreaker.instance;
    cb.resetForTests();
    for (var i = 0; i < SyncCircuitBreaker.openAfterFailures; i++) {
      cb.recordFailure(latencyMs: 10);
    }
    expect(cb.state, CircuitState.open);
    expect(cb.allowRequest(), isFalse);
    cb.forceClose(reason: 'test');
    expect(cb.state, CircuitState.closed);
    expect(cb.allowRequest(), isTrue);
  });
}
