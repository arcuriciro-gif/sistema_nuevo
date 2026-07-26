import 'dart:convert';
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

  group('SyncOutbox — reclaim no eterno', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('outbox_reclaim_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('reclaim con maxAttempts → dead (corta loop stock_op)', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-loop',
        codigo: 'ABC',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.inflight,
          'attempts': SyncOutbox.maxAttempts,
          'updated_at': old,
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:op-loop'],
      );

      final n = await SyncOutbox.instance.reclaimStaleInflight(
        olderThan: const Duration(minutes: 1),
      );
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

    test('ackStockOpsYaHechas limpia cola de stock ya aplicados', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-done',
        codigo: 'X',
        delta: 2,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-pending',
        codigo: 'Y',
        delta: 1,
      );

      final n = await SyncOutbox.instance.ackStockOpsYaHechas({'op-done'});
      expect(n, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });

    test('payload stock_op se guarda con opId', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-json',
        codigo: 'Z',
        delta: 3,
      );
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'sync_outbox',
        where: 'op_id = ?',
        whereArgs: ['stock_op:op-json'],
      );
      final payload = jsonDecode(rows.first['payload']!.toString()) as Map;
      expect(payload['opId'], 'op-json');
      expect(payload['delta'], 3);
    });
  });
}
