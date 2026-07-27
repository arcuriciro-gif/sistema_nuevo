import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/stock_real_harness.dart';
import 'package:sistema_nuevo/core/cert/stock_reference_model.dart';
import 'package:sistema_nuevo/core/cert/stock_sequence_generator.dart';
import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_ack_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_windows_apply_protocol.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:path/path.dart' as p;

/// Fase 3: intentos deliberados de romper cada Gx.
/// Cada test documenta: ataque → resultado (roto / resistido / residual).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Contraejemplos G1 — doble apply', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('cx_g1_');
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

    test('doble retry mismo eventId → resistido (1 sola fila ledger)', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'X',
        'descripcion': 'X',
        'stock': 10,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      Future<bool> once() async {
        final e = DomainEvent(
          eventId: 'venta:cx1',
          type: DomainEventType.ajusteInventario,
          aggregateType: 'venta',
          aggregateId: '1',
          createdBy: 't',
          payload: {
            'documentType': 'venta',
            'documentId': '1',
            'lines': [
              InventoryLine(productoId: id, cantidad: 2).toJson(),
            ],
          },
        );
        return db.transaction((txn) async {
          return InventoryLedgerService.instance.applyInTxn(
            txn,
            e,
            sign: -1,
            movimientoTipo: 'salida',
            enqueueOutboundStockOps: false,
          );
        });
      }

      expect(await once(), isTrue);
      expect(await once(), isFalse);
      expect(await once(), isFalse);
      final rows = await db.query(
        'inventory_ledger',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      expect(rows, hasLength(1));
    });

    test('replay remoto mismo opId → resistido', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'Y',
        'descripcion': 'Y',
        'stock': 10,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      final a = await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'op:cx',
        productoId: id,
        codigo: 'Y',
        delta: -3,
        notify: false,
      );
      final b = await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'op:cx',
        productoId: id,
        codigo: 'Y',
        delta: -3,
        notify: false,
      );
      expect(a, isTrue);
      expect(b, isFalse);
    });

    test('Windows claim: perdedor no incrementa (protocolo)', () {
      const snap = WindowsStockOpSnapshot(
        exists: true,
        status: 'claimed',
        incrementApplied: false,
        claim: 'winner',
      );
      expect(
        windowsStepMayIncrement(
          decideWindowsStockOpAfterClaim(snap: snap, ourClaim: 'loser'),
        ),
        isFalse,
      );
      expect(
        windowsStepMayIncrement(
          decideWindowsStockOpAfterClaim(snap: snap, ourClaim: 'winner'),
        ),
        isTrue,
      );
    });
  });

  group('Contraejemplos G2 — pérdida', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('cx_g2_');
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

    test('crash after commit: outbox sobrevive (no pérdida)', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'G2',
        'descripcion': 'G2',
        'stock': 5,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      final e = DomainEvent(
        eventId: 'compra:g2',
        type: DomainEventType.ajusteInventario,
        aggregateType: 'compra',
        aggregateId: 'g2',
        createdBy: 't',
        payload: {
          'documentType': 'compra',
          'documentId': 'g2',
          'lines': [
            InventoryLine(productoId: id, cantidad: 4).toJson(),
          ],
        },
      );
      await db.transaction((txn) async {
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          e,
          sign: 1,
          movimientoTipo: 'entrada',
        );
      });
      // Crash simulado = solo leer de nuevo
      final out = await db.query(
        'sync_outbox',
        where: "op_id = ?",
        whereArgs: ['stock_op:compra:g2_$id'],
      );
      expect(out, hasLength(1), reason: 'G2: outbox debe existir post-commit');
    });

    test('codigo vacío: apply se RECHAZA (no pérdida silenciosa)', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': '',
        'descripcion': 'sin-cod',
        'stock': 5,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      final e = DomainEvent(
        eventId: 'venta:empty',
        type: DomainEventType.ajusteInventario,
        aggregateType: 'venta',
        aggregateId: 'e',
        createdBy: 't',
        payload: {
          'documentType': 'venta',
          'documentId': 'e',
          'lines': [
            InventoryLine(productoId: id, cantidad: 1).toJson(),
          ],
        },
      );
      await expectLater(
        db.transaction((txn) async {
          return InventoryLedgerService.instance.applyInTxn(
            txn,
            e,
            sign: -1,
            movimientoTipo: 'salida',
            enqueueOutboundStockOps: true,
          );
        }),
        throwsA(isA<StateError>()),
      );
      // TX rollback → stock intacto, sin outbox huérfana
      final stock = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect((stock.first['stock'] as num).toInt(), 5);
      expect(await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending), 0);
    });

    test('RESIDUAL: poison dead — op no se pierde del ledger pero cloud puede quedar pendiente',
        () async {
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'poison1',
        codigo: 'P',
        delta: -1,
      );
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.dead,
          'attempts': SyncOutbox.maxAttempts,
        },
        where: 'op_id = ?',
        whereArgs: ['stock_op:poison1'],
      );
      final n = await SyncOutbox.instance.ackDeadStockOps();
      expect(n, 0, reason: 'poison no reabre solo');
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.dead),
        1,
      );
      // Contraejemplo parcial G2: convergencia cloud diferida hasta intervención.
    });
  });

  group('Contraejemplos G3 — ACK prematuro', () {
    test('política: sin proof → no ACK', () {
      expect(mayAckStockOp(cloudAppliedProven: false), isFalse);
    });

    test('modelo ref: AckIfApplied sin applied → outbox sigue', () {
      final model = StockReferenceModel();
      var s = StockRefState.initial({'A': 10});
      s = model.reduce(
        s,
        const LocalApply(eventId: 'v:1', codigo: 'A', delta: -1),
      );
      expect(s.outboxPending, contains('v:1_A'));
      s = model.reduce(s, const AckIfApplied(opId: 'v:1_A'));
      expect(s.lastError, contains('ACK rechazado'));
      expect(s.outboxPending, contains('v:1_A'));
    });

    test('clearAllStockOpsOutbox no ACK ciego', () async {
      final tmp = await Directory.systemTemp.createTemp('cx_g3_');
      SharedPreferences.setMockInitialValues({});
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 't.db'),
      );
      await SyncOutbox.instance.enqueueStockOp(
        opId: 'x',
        codigo: 'A',
        delta: 1,
      );
      expect(await SyncOutbox.instance.clearAllStockOpsOutbox(), 0);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
      await DatabaseHelper.instance.cerrar();
      await tmp.delete(recursive: true);
    });
  });

  group('Contraejemplos G4 — reconstrucción', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('cx_g4_');
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

    test('tras movimientos: stock == base + Σ ledger', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'R',
        'descripcion': 'R',
        'stock': 20,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      for (final (eid, sign, qty) in [
        ('v1', -1, 3),
        ('c1', 1, 5),
        ('r1', -1, 2),
      ]) {
        final e = DomainEvent(
          eventId: eid,
          type: DomainEventType.ajusteInventario,
          aggregateType: 'x',
          aggregateId: eid,
          createdBy: 't',
          payload: {
            'documentType': 'x',
            'documentId': eid,
            'lines': [
              InventoryLine(productoId: id, cantidad: qty).toJson(),
            ],
          },
        );
        await db.transaction((txn) async {
          await InventoryLedgerService.instance.applyInTxn(
            txn,
            e,
            sign: sign,
            movimientoTipo: sign < 0 ? 'salida' : 'entrada',
            enqueueOutboundStockOps: false,
          );
        });
      }
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(id),
        isTrue,
      );
      // 20 -3 +5 -2 = 20
      final stock = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect((stock.first['stock'] as num).toInt(), 20);
    });

    test('RESIDUAL cerrado: legacy sin ledger se migra con seed', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'LEG',
        'descripcion': 'legacy',
        'stock': 99,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      // Antes de migrar: no reconstruible
      expect(
        await InventoryLedgerService.instance.reconstruirStock(id),
        0,
      );
      // Tras LegacyLedgerMigration (R2):
      // se valida en residuales_cerrados_test — aquí solo documentamos el hueco previo.
      expect(id, greaterThan(0));
    });
  });

  group('Contraejemplos G5 — orden/reintentos', () {
    test('modelo: permutaciones + retries → mismo stock', () {
      final model = StockReferenceModel();
      final ops = [
        const LocalApply(eventId: 'a', codigo: 'A', delta: -2),
        const LocalApply(eventId: 'b', codigo: 'A', delta: 5),
        const LocalApply(eventId: 'c', codigo: 'A', delta: -1),
      ];
      final orders = [
        ops,
        ops.reversed.toList(),
        [ops[1], ops[2], ops[0]],
        [ops[2], ops[0], ops[1]],
      ];
      final results = <int>[];
      for (final order in orders) {
        var s = StockRefState.initial({'A': 10});
        s = model.reduceAll(s, [
          ...order,
          ...order.map(
            (e) => LocalReplay(
              eventId: (e as LocalApply).eventId,
              codigo: e.codigo,
              delta: e.delta,
            ),
          ),
        ]);
        results.add(s.stock['A']!);
      }
      expect(results.toSet(), {12}); // 10 -2 +5 -1
    });
  });

  group('Contraejemplos G6 — convergencia', () {
    test('modelo: offline + drain → converge tras upload+ack', () {
      final model = StockReferenceModel();
      var s = StockRefState.initial({'A': 10});
      s = model.reduceAll(s, [
        const LocalApply(eventId: 'v', codigo: 'A', delta: -4),
        const GoOffline(),
        const UploadAttempt(),
        const GoOnline(),
        const UploadAttempt(writerId: 'w1'),
        const AckIfApplied(opId: 'v_A'),
      ]);
      expect(s.cloudStatus['v_A'], RefCloudStatus.applied);
      expect(s.outboxPending, isEmpty);
      expect(s.stock['A'], s.cloudStock['A']);
      expect(s.convergedAfterSuccessfulSync(), isTrue);
    });

    test('watermark adelantado con missing product → política HOLD', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 1,
          skippedMissingProduct: 1,
        ),
        isFalse,
      );
    });

    test('watermark con pending_apply → HOLD', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 2,
          skippedMissingProduct: 0,
          skippedPendingApply: 1,
        ),
        isFalse,
      );
    });
  });

  group('Ataques red / fuera de orden (modelo)', () {
    test('dos writers mismo opId: un solo increment', () {
      final model = StockReferenceModel();
      var s = StockRefState.initial({'A': 10});
      s = model.reduce(
        s,
        const LocalApply(eventId: 'x', codigo: 'A', delta: -3),
      );
      s = model.reduce(s, const UploadAttempt(writerId: 'w1'));
      // Segundo upload tras applied
      s = model.reduce(s, const UploadAttempt(writerId: 'w2'));
      expect(s.cloudStock['A'], 7);
      expect(s.stock['A'], 7);
    });

    test('operaciones fuera de orden + replay → estable', () {
      final model = StockReferenceModel();
      final rnd = Random(7);
      final gen = StockSequenceGenerator(rnd, productos: ['A', 'B']);
      final seq = gen.generate(length: 80, includePoison: false);
      var s = StockRefState.initial({'A': 50, 'B': 50});
      s = model.reduceAll(s, seq);
      expect(s.allProjectionsConsistent, isTrue);
      // Tras drain del generador, outbox debería vaciarse o residual offline
      for (final cod in ['A', 'B']) {
        expect(s.projectionConsistent(cod), isTrue);
      }
    });
  });
}
