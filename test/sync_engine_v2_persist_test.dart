import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/scheduler/adaptive_sync_controller.dart';
import 'package:sistema_nuevo/core/sync/scheduler/scheduler_state_store.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_auto_healer.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_metrics_history_store.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_metrics.dart';
import 'package:sistema_nuevo/core/sync/scheduler/turbo_mode_controller.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Sync Engine 2.0 — persistencia / heal / claim', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('engine2_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
      SyncSchedulerMetrics.instance.resetForTests();
      AdaptiveSyncController.instance.resetForTests();
      TurboModeController.instance.resetForTests();
      SyncAutoHealer.instance.resetForTests();
      SyncScheduler.instance.resetForTests();
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('schema v35: scheduler_state + metrics_samples existen', () async {
      expect(DatabaseHelper.schemaVersion, greaterThanOrEqualTo(35));
      final db = await DatabaseHelper.instance.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((e) => e['name']).toSet();
      expect(names, contains('sync_scheduler_state'));
      expect(names, contains('sync_metrics_samples'));
      expect(names, contains('import_jobs'));
    });

    test('estado durable sobrevive "reinicio"', () async {
      await SchedulerStateStore.instance.save(
        mode: 'turbo',
        turboActive: true,
        adaptiveBatchL1: 14,
        adaptiveBatchBg: 40,
        lastFirestoreLatencyMs: 220,
        checkpoint: {'claimed': 12},
      );
      final loaded = await SchedulerStateStore.instance.load();
      expect(loaded, isNotNull);
      expect(loaded!.mode, 'turbo');
      expect(loaded.turboActive, isTrue);
      expect(loaded.adaptiveBatchL1, 14);
      expect(loaded.adaptiveBatchBg, 40);
    });

    test('historial 24h registra y limpia viejos', () async {
      await SyncMetricsHistoryStore.instance.record(
        SyncMetricsSample(
          at: DateTime.now().toUtc().toIso8601String(),
          pendingL1: 0,
          pendingL2: 1,
          pendingL3: 500,
          pendingL4: 0,
          opsPerMin: 40,
          avgLatencyMs: 180,
          maxLatencyMs: 400,
          errors: 0,
          turbo: true,
          firestoreOk: true,
        ),
      );
      final list = await SyncMetricsHistoryStore.instance.last24h();
      expect(list, isNotEmpty);
      expect(list.first.healthColor, anyOf('verde', 'amarillo'));
    });

    test('claimForTick en turbo prioriza fondo; con L1 solo crítico', () async {
      for (var i = 1; i <= 30; i++) {
        await SyncOutbox.instance.enqueueUpsert(
          entityType: 'producto',
          localId: i,
          forceBackground: true,
        );
      }
      var bd = await SyncOutbox.instance.pendingBreakdown();
      var claimed = await SyncScheduler.instance.claimForTick(
        breakdown: bd,
        isWindows: false,
      );
      expect(claimed, isNotEmpty);
      expect(
        claimed.every((e) => e['entity_type'] == 'producto'),
        isTrue,
      );
      expect(SyncScheduler.instance.turbo.active, isTrue);

      // ACK turbo batch para liberar; encolar venta.
      for (final op in claimed) {
        await SyncOutbox.instance.ack(op['op_id'] as String);
      }
      await SyncOutbox.instance.enqueueUpsert(entityType: 'venta', localId: 1);
      bd = await SyncOutbox.instance.pendingBreakdown();
      claimed = await SyncScheduler.instance.claimForTick(
        breakdown: bd,
        isWindows: false,
      );
      expect(claimed.first['entity_type'], 'venta');
      expect(
        claimed.where((e) => e['entity_type'] == 'producto'),
        isEmpty,
      );
    });

    test('auto-healer reclaim inflight viejo', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'heal-op-1',
        codigo: 'SKU-HEAL',
        delta: -1,
      );
      final claimed = await SyncOutbox.instance.claimBatch(
        limit: 1,
        entityTypes: const ['stock_op'],
      );
      expect(claimed, hasLength(1));
      final db = await DatabaseHelper.instance.database;
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      await db.update(
        'sync_outbox',
        {'updated_at': old, 'status': SyncOutboxStatus.inflight},
        where: 'op_id = ?',
        whereArgs: [claimed.first['op_id']],
      );
      final direct = await SyncOutbox.instance.reclaimStaleInflight(
        olderThan: const Duration(minutes: 1),
      );
      expect(direct, greaterThanOrEqualTo(1));
      final result = await SyncAutoHealer.instance.heal(
        staleInflight: const Duration(minutes: 1),
      );
      expect(result, isNotEmpty);
      final pending = await SyncOutbox.instance.countByStatus(
        SyncOutboxStatus.pending,
      );
      expect(pending, greaterThanOrEqualTo(1));
    });

    test('requeueImmediate no castiga attempts', () async {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: 7,
        forceBackground: true,
      );
      final claimed = await SyncOutbox.instance.claimBatch(limit: 1);
      final opId = claimed.first['op_id'] as String;
      expect(claimed.first['attempts'], 1);
      await SyncOutbox.instance.requeueImmediate(opId);
      final rows = await (await DatabaseHelper.instance.database).query(
        'sync_outbox',
        where: 'op_id = ?',
        whereArgs: [opId],
      );
      expect(rows.first['status'], SyncOutboxStatus.pending);
      expect((rows.first['attempts'] as num).toInt(), 0);
    });
  });
}
