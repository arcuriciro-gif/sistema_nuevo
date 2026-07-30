import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/import/import_checkpoint_store.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_priority.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_metrics.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncOutbox — prioridad / coalesce / scheduler', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sched_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
      SyncSchedulerMetrics.instance.resetForTests();
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('claim prioriza venta antes que miles de productos', () async {
      for (var i = 1; i <= 200; i++) {
        await SyncOutbox.instance.enqueueUpsert(
          entityType: 'producto',
          localId: i,
          forceBackground: true,
        );
      }
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'venta',
        localId: 1,
      );

      final claimed = await SyncOutbox.instance.claimBatch(
        limit: 5,
        orderByPriority: true,
      );
      expect(claimed, isNotEmpty);
      expect(claimed.first['entity_type'], 'venta');
      expect(
        (claimed.first['priority'] as num).toInt(),
        SyncPriority.critical,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('scheduler claimForTick crítico primero con backlog fondo', () async {
      for (var i = 1; i <= 80; i++) {
        await SyncOutbox.instance.enqueueUpsert(
          entityType: 'producto',
          localId: i,
          forceBackground: true,
        );
      }
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'remito',
        localId: 9,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'op-test-1',
        codigo: 'SKU1',
        delta: -1,
      );

      final breakdown = await SyncOutbox.instance.pendingBreakdown();
      final claimed = await SyncScheduler.instance.claimForTick(
        breakdown: breakdown,
        isWindows: false,
      );
      expect(claimed, isNotEmpty);
      final types = claimed.map((e) => e['entity_type']).toSet();
      expect(types.contains('remito') || types.contains('stock_op'), isTrue);
      // Con críticos, el fondo es residual (0–2).
      final productos =
          claimed.where((e) => e['entity_type'] == 'producto').length;
      expect(productos, lessThanOrEqualTo(2));
    });

    test('coalesce: N upserts mismo producto = 1 pending', () async {
      for (var i = 0; i < 5; i++) {
        await SyncOutbox.instance.enqueueUpsert(
          entityType: 'producto',
          localId: 42,
          payload: {'precio': 100.0 + i},
          forceBackground: true,
        );
      }
      final bd = await SyncOutbox.instance.pendingBreakdown();
      expect(bd['producto'], 1);
      expect(SyncSchedulerMetrics.instance.coalescedOps, greaterThan(0));
    });

    test('import checkpoint resume tras "crash"', () async {
      final store = ImportCheckpointStore.instance;
      final job = await store.startJob(
        sourceName: 'big.csv',
        totalRows: 50000,
      );
      final mid = ImportCheckpoint(
        jobId: job.jobId,
        sourceName: job.sourceName,
        totalRows: 50000,
        nextRowIndex: 12345,
        imported: 10000,
        updated: 2000,
        skipped: 345,
        status: 'running',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await store.saveProgress(mid);

      // Simula cierre: nueva lectura del running.
      final resumed = await store.loadRunning();
      expect(resumed, isNotNull);
      expect(resumed!.nextRowIndex, 12345);
      expect(resumed.imported, 10000);
      expect(resumed.progress, closeTo(12345 / 50000, 0.001));

      await store.markDone(job.jobId);
      expect(await store.loadRunning(), isNull);
    });

    test('estrés: 10k productos + 1 venta → claim venta primero', () async {
      final db = await DatabaseHelper.instance.database;
      final ahora = DateTime.now().toUtc().toIso8601String();
      final batch = <Map<String, Object?>>[];
      for (var i = 1; i <= 10000; i++) {
        batch.add({
          'op_id': 'upsert:producto:$i',
          'entity_type': 'producto',
          'entity_local_id': i,
          'operation': 'upsert',
          'status': SyncOutboxStatus.pending,
          'attempts': 0,
          'created_at': ahora,
          'updated_at': ahora,
          'priority': SyncPriority.background,
          'lane': SyncLane.background.wireName,
        });
      }
      // Insert masivo por chunks.
      const chunk = 500;
      for (var o = 0; o < batch.length; o += chunk) {
        final end = (o + chunk).clamp(0, batch.length);
        await db.transaction((txn) async {
          for (final row in batch.sublist(o, end)) {
            await txn.insert('sync_outbox', row);
          }
        });
      }
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'venta',
        localId: 777,
      );

      final sw = Stopwatch()..start();
      final claimed = await SyncOutbox.instance.claimBatch(
        limit: 20,
        orderByPriority: true,
      );
      sw.stop();
      expect(claimed.first['entity_type'], 'venta');
      expect(sw.elapsedMilliseconds, lessThan(5000));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
