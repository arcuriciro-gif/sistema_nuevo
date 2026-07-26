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

    test('clearAllStockOpsOutbox limpia pending/inflight/dead', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'a',
        codigo: 'A',
        delta: 1,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'b',
        codigo: 'B',
        delta: -1,
      );
      await SyncOutbox.instance.ack('stock_op:a');
      // Forzar dead en b vía fail max
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': 99,
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:b'],
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'c',
        codigo: 'C',
        delta: 2,
      );

      final n = await SyncOutbox.instance.clearAllStockOpsOutbox();
      expect(n, greaterThanOrEqualTo(2));
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.dead),
        0,
      );
    });

    test('ackDeadStockOps reencola dead; no ACK ciego; deja fresco', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'fresh',
        codigo: 'F',
        delta: 1,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'dead-one',
        codigo: 'D',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': 99,
          'last_error': 'boom',
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:dead-one'],
      );

      final n = await SyncOutbox.instance.ackDeadStockOps();
      expect(n, 1);
      // fresh + dead reencolado
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        2,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.dead),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        0,
      );
    });

    test('purgeStuckStockOps sin prueba reencola (no ACK ciego)', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-stuck',
        codigo: 'S',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'attempts': 5,
          'last_error': 'reclaimed_stale_inflight',
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:op-stuck'],
      );

      final n = await SyncOutbox.instance.purgeStuckStockOps(
        minAttempts: 2,
        onlyLastErrorContains: 'reclaimed_stale_inflight',
      );
      expect(n, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });

    test('purgeStuckStockOps ACK solo con prueba cloud', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-ok',
        codigo: 'S',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'attempts': 5,
          'last_error': 'reclaimed_stale_inflight',
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:op-ok'],
      );

      final n = await SyncOutbox.instance.purgeStuckStockOps(
        minAttempts: 2,
        onlyLastErrorContains: 'reclaimed_stale_inflight',
        proveCloudApplied: (remoteId) async => remoteId == 'op-ok',
      );
      expect(n, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
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
