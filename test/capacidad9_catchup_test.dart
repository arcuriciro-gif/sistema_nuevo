import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/sync_catchup.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 9 — outbox catch-up', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('c9_catchup_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('needsCatchupUpsert: vacío=true, acked=false, dead=true', () async {
      expect(
        await SyncOutbox.instance.needsCatchupUpsert(
          entityType: 'remito',
          localId: 1,
        ),
        isTrue,
      );

      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'remito',
        localId: 1,
      );
      await SyncOutbox.instance.ack('upsert:remito:1');
      expect(
        await SyncOutbox.instance.needsCatchupUpsert(
          entityType: 'remito',
          localId: 1,
        ),
        isFalse,
      );

      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': SyncOutbox.maxAttempts,
        },
        where: 'op_id = ?',
        whereArgs: ['upsert:remito:1'],
      );
      expect(
        await SyncOutbox.instance.needsCatchupUpsert(
          entityType: 'remito',
          localId: 1,
        ),
        isTrue,
      );
    });

    test('catch-up pagina y avanza cursor; no reencola acked', () async {
      final db = await DatabaseHelper.instance.database;
      for (var i = 0; i < 5; i++) {
        await db.insert('remitos', {
          'numero': 'R-C9-${i + 1}',
          'fecha': DateTime.now().toIso8601String(),
          'total': 10,
          'estado': 'pendiente',
          'estadoPago': 'pendiente',
          'totalPagado': 0,
          'saldoPendiente': 10,
        });
      }

      final n1 = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'remitos',
        entityType: 'remito',
        pageSize: 2,
        maxPagesPerCycle: 1,
      );
      expect(n1, 2);
      expect(await SyncCatchup.instance.loadCursor('remito'), 2);

      // ACK de los encolados.
      final pending = await db.query(
        'sync_outbox',
        where: 'status = ?',
        whereArgs: [SyncOutboxStatus.pending],
      );
      for (final row in pending) {
        await SyncOutbox.instance.ack(row['op_id']!.toString());
      }

      final n2 = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'remitos',
        entityType: 'remito',
        pageSize: 2,
        maxPagesPerCycle: 2,
      );
      // ids 3,4,5 → 3 nuevos; no reencola 1–2 acked
      expect(n2, 3);

      final n3 = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'remitos',
        entityType: 'remito',
        pageSize: 2,
        maxPagesPerCycle: 2,
      );
      // fin de tabla → cursor reset; nada nuevo que encolar
      expect(n3, 0);
      expect(await SyncCatchup.instance.loadCursor('remito'), 0);
    });
  });
}
