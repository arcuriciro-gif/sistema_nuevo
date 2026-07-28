import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/g6_eventual_consistency.dart';
import 'package:sistema_nuevo/core/cert/stock_reference_model.dart';
import 'package:sistema_nuevo/core/cert/stock_sequence_generator.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/integrity/legacy_ledger_migration.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_hold_store.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Cierre de residuales: poison, legacy ledger, G6 formal, watermark HOL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('R1 — poison / dead queue gestión completa', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('r1_dead_');
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

    test('recoverDead: cloud applied → ACK; poison → force requeue', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'applied-op',
        codigo: 'A',
        delta: -1,
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'poison-op',
        codigo: 'B',
        delta: 2,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': SyncOutbox.maxAttempts,
        },
        where: "entity_type = 'stock_op'",
      );

      final r = await SyncOutbox.instance.recoverDeadStockOps(
        proveCloudApplied: (id) async => id == 'applied-op',
      );
      expect(r.acked, 1);
      expect(r.forceRequeued, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.dead),
        0,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
    });

    test('forceRequeuePoisonStockOps reabre attempts>=max', () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'p1',
        codigo: 'X',
        delta: 1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': 99,
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:p1'],
      );
      expect(await SyncOutbox.instance.ackDeadStockOps(), 0);
      expect(await SyncOutbox.instance.forceRequeuePoisonStockOps(), 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });
  });

  group('R2 — migración histórico → ledger', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('r2_leg_');
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

    test('seedMissing: stock intacto + proyección verificable + idempotente',
        () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'LEG',
        'descripcion': 'legacy',
        'stock': 42,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      expect(await LegacyLedgerMigration.instance.countMissing(), 1);
      expect(await LegacyLedgerMigration.instance.seedMissing(), 1);
      expect(await LegacyLedgerMigration.instance.seedMissing(), 0);
      expect(await LegacyLedgerMigration.instance.countMissing(), 0);

      final stock = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect((stock.first['stock'] as num).toInt(), 42);
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(id),
        isTrue,
      );
      final recon = await InventoryLedgerService.instance.reconstruirStock(
        id,
        stockInicial: 0,
      );
      expect(recon, 42);
    });
  });

  group('R3 — G6 convergencia eventual formal', () {
    test('evaluateG6: quiescent + stocks iguales → ok', () {
      final v = evaluateG6(
        localStock: {'A': 7},
        cloudStock: {'A': 7},
        outboxPending: 0,
        outboxInflight: 0,
        outboxDead: 0,
        deadWithoutCloudApplied: 0,
        pullHolds: 0,
        online: true,
        localOriginOpIds: ['op1'],
        cloudOpStatus: {'op1': 'applied'},
      );
      expect(v.ok, isTrue);
    });

    test('evaluateG6: dead sin applied → no quiescent', () {
      final v = evaluateG6(
        localStock: {'A': 7},
        cloudStock: {'A': 7},
        outboxPending: 0,
        outboxInflight: 0,
        outboxDead: 1,
        deadWithoutCloudApplied: 1,
        pullHolds: 0,
        online: true,
        localOriginOpIds: ['op1'],
        cloudOpStatus: {'op1': 'pending_apply'},
      );
      expect(v.quiescent, isFalse);
      expect(v.converged, isFalse);
    });

    test('modelo: 300 secuencias + drain hasta quiescencia → G6 ok', () {
      final model = StockReferenceModel();
      final rnd = Random(123);
      final gen = StockSequenceGenerator(rnd, productos: ['A', 'B']);
      for (var i = 0; i < 300; i++) {
        final seq = gen
            .generate(length: 25, includePoison: false)
            .where((e) => e is! RemoteApply)
            .toList();
        var s = StockRefState.initial({'A': 50, 'B': 50});
        s = model.reduceAll(s, seq);
        // Schedule finito de drain (definición G6).
        for (var k = 0; k < 80; k++) {
          s = model.reduce(s, const GoOnline());
          s = model.reduce(s, const UploadAttempt(writerId: 'drain'));
          for (final op in List<String>.from(s.outboxPending)) {
            s = model.reduce(s, AckIfApplied(opId: op));
          }
          if (s.outboxPending.isEmpty) break;
        }
        final originOps = s.cloudDelta.keys.toList();
        final status = <String, String>{
          for (final e in s.cloudStatus.entries)
            e.key: switch (e.value) {
              RefCloudStatus.applied => 'applied',
              RefCloudStatus.pendingApply => 'pending_apply',
              RefCloudStatus.claimed => 'claimed',
              RefCloudStatus.missing => 'missing',
            },
        };
        for (final op in originOps) {
          status.putIfAbsent(op, () => 'missing');
        }
        final v = evaluateG6(
          localStock: s.stock,
          cloudStock: s.cloudStock,
          outboxPending: s.outboxPending.length,
          outboxInflight: 0,
          outboxDead: s.outboxDead.length,
          deadWithoutCloudApplied: s.outboxDead.length,
          pullHolds: 0,
          online: true,
          localOriginOpIds: originOps,
          cloudOpStatus: status,
        );
        expect(
          v.ok,
          isTrue,
          reason: 'G6 fail seq#$i reasons=${v.reasons}\n${encodeSequence(seq)}',
        );
      }
    });
  });

  group('R4 — watermark HOL / hold-set', () {
    test('missing parked → advance; pending parked → NO', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 2,
          skippedMissingProduct: 1,
          skippedPendingApply: 0,
          blockersParkedInHolds: true,
        ),
        isTrue,
      );
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 2,
          skippedMissingProduct: 1,
          skippedPendingApply: 1,
          blockersParkedInHolds: true,
        ),
        isFalse,
      );
    });

    test('blockers sin park → NO advance (no pérdida)', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 2,
          skippedMissingProduct: 1,
          skippedPendingApply: 0,
          blockersParkedInHolds: false,
        ),
        isFalse,
      );
    });

    test('hold store upsert/remove/count', () async {
      final tmp = await Directory.systemTemp.createTemp('r4_hold_');
      SharedPreferences.setMockInitialValues({});
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 't.db'),
      );
      await StockOpsPullHoldStore.instance.upsert(
        opId: 'op-hold',
        reason: StockOpsPullHoldStore.reasonMissingProduct,
        codigo: 'Z',
        delta: -1,
      );
      expect(await StockOpsPullHoldStore.instance.count(), 1);
      expect(await StockOpsPullHoldStore.instance.contains('op-hold'), isTrue);
      final due = await StockOpsPullHoldStore.instance.listDue();
      expect(due, hasLength(1));
      await StockOpsPullHoldStore.instance.remove('op-hold');
      expect(await StockOpsPullHoldStore.instance.count(), 0);
      await DatabaseHelper.instance.cerrar();
      await tmp.delete(recursive: true);
    });

    test('schema v39 (proveedores.actualizadoEn)', () {
      expect(DatabaseHelper.schemaVersion, greaterThanOrEqualTo(39));
    });
  });
}
