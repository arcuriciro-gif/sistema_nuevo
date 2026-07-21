import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/core/sync/sync_tombstone.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 7 — tombstone helpers', () {
    test('isRemoteTombstone reconoce tombstone y deletedAt', () {
      expect(isRemoteTombstone(null), isFalse);
      expect(isRemoteTombstone({}), isFalse);
      expect(isRemoteTombstone({'tombstone': true}), isTrue);
      expect(
        isRemoteTombstone({'deletedAt': '2026-07-21T12:00:00.000Z'}),
        isTrue,
      );
      expect(isRemoteTombstone({'deletedAt': ''}), isFalse);
    });

    test('buildTombstonePayload incluye opId estable', () {
      final payload = buildTombstonePayload(
        opId: 'delete:remito:R-1',
        deletedBy: 'uid-1',
        at: DateTime.utc(2026, 7, 21, 12),
      );
      expect(payload['tombstone'], isTrue);
      expect(payload['opId'], 'delete:remito:R-1');
      expect(payload['deletedBy'], 'uid-1');
      expect(payload['deletedAt'], '2026-07-21T12:00:00.000Z');
    });
  });

  group('Capacidad 7 — outbox delete antes de hard-delete', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('c7_delete_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('enqueueDelete deja pending aunque la fila local siga existiendo',
        () async {
      final db = await DatabaseHelper.instance.database;
      final remitoId = await db.insert('remitos', {
        'numero': 'R-C7-001',
        'fecha': DateTime.now().toIso8601String(),
        'total': 100,
        'estado': 'pendiente',
        'estadoPago': 'pendiente',
        'totalPagado': 0,
        'saldoPendiente': 100,
      });

      await SyncOutbox.instance.enqueueDelete(
        entityType: 'remito',
        remoteId: 'R-C7-001',
        localId: remitoId,
      );

      expect(
        await SyncOutbox.instance.hasPendingDelete(
          entityType: 'remito',
          remoteId: 'R-C7-001',
        ),
        isTrue,
      );

      final stillThere = await db.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [remitoId],
      );
      expect(stillThere, isNotEmpty);

      final counts = await SyncOutbox.instance.counts();
      expect(counts[SyncOutboxStatus.pending], greaterThanOrEqualTo(1));
    });

    test('enqueueStockOp es durable e idempotente por opId', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-abc',
        codigo: 'SKU1',
        delta: -2,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-abc',
        codigo: 'SKU1',
        delta: -2,
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'sync_outbox',
        where: 'op_id = ?',
        whereArgs: ['stock_op:op-abc'],
      );
      expect(rows.length, 1);
      expect(rows.first['status'], SyncOutboxStatus.pending);
      expect(rows.first['entity_type'], 'stock_op');
    });
  });
}
