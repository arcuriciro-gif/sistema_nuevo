import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/event_bus.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/domain/money_ledger_service.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 3 — contratos de eventos', () {
    test('tipos de inventario y dinero son estables', () {
      expect(DomainEventType.mercaderiaEntregada, 'MERCADERIA_ENTREGADA');
      expect(DomainEventType.mercaderiaRecibida, 'MERCADERIA_RECIBIDA');
      expect(DomainEventType.ajusteInventario, 'AJUSTE_INVENTARIO');
      expect(DomainEventType.ventaCargadaCc, 'VENTA_CARGADA_CC');
      expect(DomainEventType.ventaCcRevertida, 'VENTA_CC_REVERTIDA');
      expect(DomainEventType.pagoRegistrado, 'PAGO_REGISTRADO');
    });

    test('InventoryLine serializa round-trip', () {
      final line = InventoryLine(
        productoId: 7,
        cantidad: 3,
        productoCodigo: 'ABC',
      );
      final again = InventoryLine.fromJson(line.toJson());
      expect(again.productoId, 7);
      expect(again.cantidad, 3);
      expect(again.productoCodigo, 'ABC');
    });
  });

  group('Capacidad 3 — Event Bus', () {
    tearDown(() {
      DomainEventBus.instance.resetForTests();
    });

    test('publish invoca handlers tipados en orden', () async {
      final seen = <String>[];
      DomainEventBus.instance.subscribe(DomainEventType.ajusteInventario, (e) {
        seen.add('typed:${e.eventId}');
      });
      DomainEventBus.instance.subscribeAll((e) {
        seen.add('any:${e.type}');
      });

      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'e1',
          type: DomainEventType.ajusteInventario,
          payload: const {},
        ),
      );

      expect(seen, ['typed:e1', 'any:AJUSTE_INVENTARIO']);
    });
  });

  group('Capacidad 3 — ledgers (SQLite)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('c3_ledger_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
      DomainBootstrap.resetForTests();
      DomainBootstrap.ensureInitialized();
    });

    tearDown(() async {
      DomainBootstrap.resetForTests();
      try {
        await DatabaseHelper.instance.resetForTests(
          absolutePath: p.join(tmp.path, 'closed.db'),
        );
      } catch (_) {}
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    Future<int> seedProducto({int stock = 10}) async {
      final db = await DatabaseHelper.instance.database;
      return db.insert('productos', {
        'codigo': 'P-${DateTime.now().microsecondsSinceEpoch}',
        'descripcion': 'Producto test',
        'stock': stock,
        'precio': 100,
        'costo': 50,
      });
    }

    test('entrega baja stock; idempotencia no duplica', () async {
      final productoId = await seedProducto(stock: 10);

      final event = DomainEvent(
        eventId: 'inv:test:entrega:1',
        type: DomainEventType.mercaderiaEntregada,
        payload: {
          'documentType': 'remito',
          'documentId': '1',
          'motivo': 'test',
          'lines': [
            InventoryLine(productoId: productoId, cantidad: 4).toJson(),
          ],
        },
      );

      await DomainEventBus.instance.publish(event);
      await DomainEventBus.instance.publish(event); // idempotente

      final db = await DatabaseHelper.instance.database;
      final prod = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [productoId],
      );
      expect(prod.first['stock'], 6);

      final ledger = await db.query(
        'inventory_ledger',
        where: 'parent_event_id = ?',
        whereArgs: [event.eventId],
      );
      expect(ledger.length, 1);

      final recon =
          await InventoryLedgerService.instance.reconstruirStock(productoId);
      // stockInicial=0 ⇒ reconstrucción solo del ledger C3 (= -4), no el seed.
      expect(recon, -4);
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(productoId),
        isFalse,
      );
      // Con stock inicial conocido, proyección cuadra.
      expect(
        await InventoryLedgerService.instance
            .reconstruirStock(productoId, stockInicial: 10),
        6,
      );
    });

    test('compra/recepción + reverso reconstruyen stock', () async {
      final productoId = await seedProducto(stock: 0);

      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'inv:test:rec:1',
          type: DomainEventType.mercaderiaRecibida,
          payload: {
            'documentType': 'compra',
            'documentId': '9',
            'lines': [
              InventoryLine(productoId: productoId, cantidad: 5).toJson(),
            ],
          },
        ),
      );
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'inv:test:rec_rev:1',
          type: DomainEventType.mercaderiaRecepcionRevertida,
          payload: {
            'documentType': 'compra',
            'documentId': '9',
            'lines': [
              InventoryLine(productoId: productoId, cantidad: 5).toJson(),
            ],
          },
        ),
      );

      final db = await DatabaseHelper.instance.database;
      final prod = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [productoId],
      );
      expect(prod.first['stock'], 0);
      expect(
        await InventoryLedgerService.instance.reconstruirStock(productoId),
        0,
      );
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(productoId),
        isTrue,
      );
    });

    test('money ledger: venta + pago + anulación = neto coherente', () async {
      const clienteId = 42;

      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:test:venta:1',
          type: DomainEventType.ventaCargadaCc,
          payload: {
            'clienteId': clienteId,
            'ventaId': 1,
            'total': 100.0,
            'motivo': 'venta test',
          },
        ),
      );
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:test:pago:1',
          type: DomainEventType.pagoRegistrado,
          payload: {
            'clienteId': clienteId,
            'ventaId': 1,
            'pagoId': 1,
            'monto': 30.0,
          },
        ),
      );

      var saldo = await MoneyLedgerService.instance
          .reconstruirSaldo('cliente_cc', '$clienteId');
      expect(saldo, 70.0);

      // Idempotencia
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:test:pago:1',
          type: DomainEventType.pagoRegistrado,
          payload: {
            'clienteId': clienteId,
            'ventaId': 1,
            'pagoId': 1,
            'monto': 30.0,
          },
        ),
      );
      saldo = await MoneyLedgerService.instance
          .reconstruirSaldo('cliente_cc', '$clienteId');
      expect(saldo, 70.0);

      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:test:venta_rev:1',
          type: DomainEventType.ventaCcRevertida,
          payload: {
            'clienteId': clienteId,
            'ventaId': 1,
            'monto': 70.0,
          },
        ),
      );
      saldo = await MoneyLedgerService.instance
          .reconstruirSaldo('cliente_cc', '$clienteId');
      expect(saldo, 0.0);
    });
  });
}
