import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/integrity/stock_integrity_validator.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Demostración G1–G6 sobre ledger local + outbox atómico.
///
/// Secuencias adversas: ventas/compras/remitos (como deltas),
/// reintentos, reordenamientos, "crash" post-commit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('garantias_g_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 'test.db'),
    );
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrar();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<int> seedProducto({
    required String codigo,
    int stock = 100,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('productos', {
      'codigo': codigo,
      'descripcion': codigo,
      'stock': stock,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> stockOf(int id) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return (r.first['stock'] as num).toInt();
  }

  Future<bool> applyLocal({
    required String eventId,
    required int productoId,
    required int sign,
    required int cantidad,
    required String documentType,
    required String documentId,
    bool enqueue = true,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final event = DomainEvent(
      eventId: eventId,
      type: DomainEventType.ajusteInventario,
      aggregateType: documentType,
      aggregateId: documentId,
      createdBy: 'test',
      payload: {
        'documentType': documentType,
        'documentId': documentId,
        'motivo': documentType,
        'lines': [
          InventoryLine(productoId: productoId, cantidad: cantidad).toJson(),
        ],
      },
    );
    return db.transaction((txn) async {
      return InventoryLedgerService.instance.applyInTxn(
        txn,
        event,
        sign: sign,
        movimientoTipo: sign < 0 ? 'salida' : 'entrada',
        enqueueOutboundStockOps: enqueue,
      );
    });
  }

  group('G1 — ninguna operación se aplica dos veces', () {
    test('mismo eventId local → segundo apply es no-op', () async {
      final id = await seedProducto(codigo: 'G1A');
      final a = await applyLocal(
        eventId: 'venta:1',
        productoId: id,
        sign: -1,
        cantidad: 3,
        documentType: 'venta',
        documentId: '1',
      );
      final b = await applyLocal(
        eventId: 'venta:1',
        productoId: id,
        sign: -1,
        cantidad: 3,
        documentType: 'venta',
        documentId: '1',
      );
      expect(a, isTrue);
      expect(b, isFalse);
      expect(await stockOf(id), 97);
    });

    test('mismo opId remoto → segundo applyRemote es no-op', () async {
      final id = await seedProducto(codigo: 'G1B');
      final ledger = InventoryLedgerService.instance;
      final a = await ledger.applyRemoteStockOp(
        opId: 'peer:op1',
        productoId: id,
        codigo: 'G1B',
        delta: -5,
        documentType: 'remito',
        documentId: 'R1',
        notify: false,
      );
      final b = await ledger.applyRemoteStockOp(
        opId: 'peer:op1',
        productoId: id,
        codigo: 'G1B',
        delta: -5,
        documentType: 'remito',
        documentId: 'R1',
        notify: false,
      );
      expect(a, isTrue);
      expect(b, isFalse);
      expect(await stockOf(id), 95);
    });
  });

  group('G2 — ninguna operación se pierde (ledger+outbox atómicos)', () {
    test('tras commit: ledger + outbox + stock_ops_applied existen', () async {
      final id = await seedProducto(codigo: 'G2A');
      await applyLocal(
        eventId: 'compra:9',
        productoId: id,
        sign: 1,
        cantidad: 10,
        documentType: 'compra',
        documentId: '9',
      );

      final db = await DatabaseHelper.instance.database;
      final ledger = await db.query(
        'inventory_ledger',
        where: 'parent_event_id = ?',
        whereArgs: ['compra:9'],
      );
      expect(ledger, hasLength(1));

      // stockOpCloudId = local_<eventId>_<productoId> (sin deviceId en tests).
      final cloudOpId = 'local_compra:9_$id';
      final outbox = await db.query(
        'sync_outbox',
        where: 'op_id = ?',
        whereArgs: ['stock_op:$cloudOpId'],
      );
      expect(outbox, hasLength(1));
      expect(outbox.first['status'], SyncOutboxStatus.pending);

      final applied = await db.query(
        'stock_ops_applied',
        where: 'op_id = ?',
        whereArgs: [cloudOpId],
      );
      expect(applied, hasLength(1));
      expect(applied.first['origin'], 'local');
    });

    test('crash simulado post-commit: outbox sobrevive; re-apply no duplica',
        () async {
      final id = await seedProducto(codigo: 'G2B');
      await applyLocal(
        eventId: 'remito:7',
        productoId: id,
        sign: -1,
        cantidad: 4,
        documentType: 'remito',
        documentId: '7',
      );
      // "Crash" = proceso conexión: outbox sigue pending; reintento local.
      final again = await applyLocal(
        eventId: 'remito:7',
        productoId: id,
        sign: -1,
        cantidad: 4,
        documentType: 'remito',
        documentId: '7',
      );
      expect(again, isFalse);
      expect(await stockOf(id), 96);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
    });
  });

  group('G4 — ledger y stock consistentes', () {
    test('venta+compra+remito+ajuste: validator sin divergencias', () async {
      final id = await seedProducto(codigo: 'G4A', stock: 50);
      await applyLocal(
        eventId: 'v:1',
        productoId: id,
        sign: -1,
        cantidad: 5,
        documentType: 'venta',
        documentId: '1',
        enqueue: false,
      );
      await applyLocal(
        eventId: 'c:1',
        productoId: id,
        sign: 1,
        cantidad: 20,
        documentType: 'compra',
        documentId: '1',
        enqueue: false,
      );
      await applyLocal(
        eventId: 'r:1',
        productoId: id,
        sign: -1,
        cantidad: 8,
        documentType: 'remito',
        documentId: '1',
        enqueue: false,
      );
      await applyLocal(
        eventId: 'a:1',
        productoId: id,
        sign: 1,
        cantidad: 3,
        documentType: 'ajuste',
        documentId: '1',
        enqueue: false,
      );
      // 50 -5 +20 -8 +3 = 60
      expect(await stockOf(id), 60);
      expect(await InventoryLedgerService.instance.verificarProyeccion(id), isTrue);
      final issues = await StockIntegrityValidator.instance.validateAll();
      expect(issues, isEmpty);
    });
  });

  group('G5 — stock reconstruible solo desde ledger', () {
    test('reconstruirStock(base) == proyección', () async {
      final id = await seedProducto(codigo: 'G5A', stock: 40);
      await applyLocal(
        eventId: 'v:g5',
        productoId: id,
        sign: -1,
        cantidad: 7,
        documentType: 'venta',
        documentId: 'g5',
        enqueue: false,
      );
      await applyLocal(
        eventId: 'c:g5',
        productoId: id,
        sign: 1,
        cantidad: 2,
        documentType: 'compra',
        documentId: 'g5',
        enqueue: false,
      );
      final db = await DatabaseHelper.instance.database;
      final first = await db.query(
        'inventory_ledger',
        columns: ['stock_before'],
        where: 'product_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
        limit: 1,
      );
      final base = (first.first['stock_before'] as num).toInt();
      final recon = await InventoryLedgerService.instance.reconstruirStock(
        id,
        stockInicial: base,
      );
      expect(recon, await stockOf(id));
      expect(recon, 35); // 40 -7 +2
    });

    test('peer seed=0 + applyRemote ops = origen', () async {
      // Origen
      final origenId = await seedProducto(codigo: 'G5PEER', stock: 100);
      await applyLocal(
        eventId: 'origen:v1',
        productoId: origenId,
        sign: -1,
        cantidad: 15,
        documentType: 'venta',
        documentId: 'v1',
        enqueue: false,
      );
      await applyLocal(
        eventId: 'origen:c1',
        productoId: origenId,
        sign: 1,
        cantidad: 5,
        documentType: 'compra',
        documentId: 'c1',
        enqueue: false,
      );
      final esperado = await stockOf(origenId);

      // Peer: producto nuevo stock 0 + ops remotas
      final peerId = await seedProducto(codigo: 'G5PEER2', stock: 0);
      // Semilla inicial del origen como primera op (stock_ops históricos)
      await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'seed:100',
        productoId: peerId,
        codigo: 'G5PEER2',
        delta: 100,
        notify: false,
      );
      await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'origen:v1_$origenId',
        productoId: peerId,
        codigo: 'G5PEER2',
        delta: -15,
        notify: false,
      );
      await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'origen:c1_$origenId',
        productoId: peerId,
        codigo: 'G5PEER2',
        delta: 5,
        notify: false,
      );
      expect(await stockOf(peerId), esperado);
    });
  });

  group('G6 — idempotencia: orden de reintentos no cambia el resultado', () {
    test('permutaciones de ops distintas → mismo stock final', () async {
      final ops = <({String id, int delta})>[
        (id: 'venta:a', delta: -3),
        (id: 'compra:b', delta: 10),
        (id: 'remito:c', delta: -2),
        (id: 'ajuste:d', delta: 1),
      ];
      final net = ops.fold<int>(0, (s, o) => s + o.delta);
      const base = 50;

      Future<int> runOrder(List<({String id, int delta})> order) async {
        final dir = await Directory.systemTemp.createTemp('g6_');
        await DatabaseHelper.instance.resetForTests(
          absolutePath: p.join(dir.path, 't.db'),
        );
        final id = await seedProducto(codigo: 'G6', stock: base);
        for (final op in order) {
          await InventoryLedgerService.instance.applyRemoteStockOp(
            opId: op.id,
            productoId: id,
            codigo: 'G6',
            delta: op.delta,
            notify: false,
          );
        }
        // Reintentos en orden inverso (duplicados)
        for (final op in order.reversed) {
          await InventoryLedgerService.instance.applyRemoteStockOp(
            opId: op.id,
            productoId: id,
            codigo: 'G6',
            delta: op.delta,
            notify: false,
          );
        }
        final s = await stockOf(id);
        await DatabaseHelper.instance.cerrar();
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
        return s;
      }

      final orders = <List<({String id, int delta})>>[
        List.of(ops),
        List.of(ops.reversed),
        [ops[2], ops[0], ops[3], ops[1]],
        [ops[1], ops[3], ops[0], ops[2]],
      ];
      // Shuffle determinista
      final rnd = Random(42);
      final shuffled = List.of(ops)..shuffle(rnd);
      orders.add(shuffled);

      final results = <int>[];
      for (final o in orders) {
        results.add(await runOrder(o));
      }
      // Restaurar DB del setUp para tearDown
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );

      expect(results.toSet(), {base + net});
      expect(results.every((r) => r == base + net), isTrue);
    });
  });
}
