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

    test('aggressive limpia docs viejos y deja fresco intacto', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 1,
        remoteId: 'SKU1',
      );
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 2,
        remoteId: 'SKU2',
      );
      final db = await DatabaseHelper.instance.database;
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      await db.update(
        'sync_outbox',
        {'attempts': 2, 'updated_at': old, 'last_error': 'circuit_open'},
        where: "op_id = 'upsert:producto:1'",
      );
      // localId 2 queda fresco (attempts 0).

      final n = await SyncOutbox.instance.quietWindowsGhostQueue(
        aggressive: true,
      );
      expect(n, greaterThanOrEqualTo(1));
      final pending = await db.query(
        'sync_outbox',
        where: 'status = ?',
        whereArgs: [SyncOutboxStatus.pending],
      );
      expect(pending.length, 1);
      expect(pending.first['op_id'], 'upsert:producto:2');
    });
  });
}
