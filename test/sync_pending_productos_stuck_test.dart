import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Bug campo: al reinstalar EXE aparecen siempre los mismos 5 productos
/// pending con intentos 0.
///
/// Causa: la DB SQLite en AppData NO se borra al reinstalar el EXE.
/// Esos IDs quedan en sync_outbox. Además "Actualizar ahora" no drenaba
/// productos (solo pull + 1 tick) y un backoff futuro los dejaba invisibles
/// al claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('pending5_');
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

  test('clearBackoffPending libera next_attempt_at → claim toma los 5',
      () async {
    final future = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    for (final id in [2, 3, 4, 5, 2899]) {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: id,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {'next_attempt_at': future, 'attempts': 0},
        where: 'op_id = ?',
        whereArgs: ['upsert:producto:$id'],
      );
    }

    var batch = await SyncOutbox.instance.claimBatch(
      limit: 10,
      entityTypes: const ['producto'],
    );
    expect(batch, isEmpty, reason: 'backoff futuro bloquea claim');

    final n = await SyncOutbox.instance.clearBackoffPending(
      entityType: 'producto',
    );
    expect(n, 5);

    batch = await SyncOutbox.instance.claimBatch(
      limit: 10,
      entityTypes: const ['producto'],
    );
    expect(batch.length, 5);
    expect(
      batch.map((e) => (e['entity_local_id'] as num).toInt()).toSet(),
      {2, 3, 4, 5, 2899},
    );
  });

  test('ACK orphan si el producto local ya no existe', () async {
    await SyncOutbox.instance.enqueueUpsert(
      entityType: 'producto',
      localId: 99999,
    );
    final n = await SyncOutbox.instance.ackOrphanUpserts();
    expect(n, 1);
    final bd = await SyncOutbox.instance.pendingBreakdown();
    expect(bd['producto'] ?? 0, 0);
  });
}
