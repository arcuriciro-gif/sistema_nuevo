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

  group('SyncOutbox — no fantasmas acked', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('outbox_acked_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('reopenAcked:false no reabre ops ya sincronizadas', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 16,
      );
      await SyncOutbox.instance.ack('upsert:producto:16');
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );

      // Simula dump de cola legacy al login Windows.
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 16,
        reopenAcked: false,
      );

      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
    });

    test('reopenAcked:true (edición usuario) sí reabre acked', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 7,
      );
      await SyncOutbox.instance.ack('upsert:producto:7');

      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 7,
        reopenAcked: true,
      );

      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        0,
      );
    });

    test('fail no pisa un ACK concurrente', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'cliente',
        localId: 3,
      );
      await SyncOutbox.instance.ack('upsert:cliente:3');

      await SyncOutbox.instance.fail('upsert:cliente:3', 'race');

      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        0,
      );
    });

    test('migrateLegacyIdSet no reabre acked', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'venta',
        localId: 1,
      );
      await SyncOutbox.instance.ack('upsert:venta:1');

      await SyncOutbox.instance.migrateLegacyIdSet(
        entityType: 'venta',
        ids: const [1, 2],
      );

      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
      // Solo el id 2 (nuevo) queda pending.
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });
  });
}
