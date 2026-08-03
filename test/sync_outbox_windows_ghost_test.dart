import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncOutbox — quiet Windows ghosts', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('outbox_ghost_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('producto con reintentos → ACK (no queda pendiente fantasma)', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 1,
        remoteId: 'SKU1',
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'attempts': 4,
          'last_error': 'reclaimed_stale_inflight',
        },
        where: "entity_type = 'producto'",
      );

      final n = await SyncOutbox.instance.quietWindowsGhostQueue();
      expect(n, greaterThanOrEqualTo(1));
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.inflight),
        0,
      );
    });

    test('stock_op fresco sin loop NO se borra', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'fresh-op',
        codigo: 'ABC',
        delta: -1,
      );
      final n = await SyncOutbox.instance.quietWindowsGhostQueue();
      expect(n, 0);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });

    test('stock_op en loop reclaim → dead (corta bucle)', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'loop-op',
        codigo: 'ABC',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'attempts': 9,
          'last_error': 'reclaimed_stale_inflight',
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:loop-op'],
      );
      final n = await SyncOutbox.instance.quietWindowsGhostQueue();
      expect(n, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.dead),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        0,
      );
    });
  });
}
