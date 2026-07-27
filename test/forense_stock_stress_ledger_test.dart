import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/integrity/stock_integrity_validator.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Estrés de ledger local: miles de movimientos + validador forense.
/// Escala CI: 200 productos × 50 ops = 10_000 movimientos.
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
    tmp = await Directory.systemTemp.createTemp('forense_stress_');
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

  test('10k movimientos: proyección == ledger; sin dobles', () async {
    final db = await DatabaseHelper.instance.database;
    const nProductos = 200;
    const opsPorProducto = 50; // 10_000 movimientos
    final now = DateTime.now().toUtc();

    for (var i = 1; i <= nProductos; i++) {
      await db.insert('productos', {
        'codigo': 'P$i',
        'descripcion': 'Prod $i',
        'stock': 1000,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': now.toIso8601String(),
      });
    }

    final ledger = InventoryLedgerService.instance;
    for (var round = 0; round < opsPorProducto; round++) {
      for (var i = 1; i <= nProductos; i++) {
        final event = DomainEvent(
          eventId: 'stress:$round:$i',
          type: DomainEventType.ajusteInventario,
          aggregateType: 'producto',
          aggregateId: '$i',
          createdBy: 'test',
          payload: {
            'documentType': 'ajuste',
            'documentId': 'stress:$round:$i',
            'motivo': 'stress',
            'lines': [
              InventoryLine(productoId: i, cantidad: 1).toJson(),
            ],
          },
        );
        await db.transaction((txn) async {
          await ledger.applyInTxn(
            txn,
            event,
            sign: round.isEven ? -1 : 1,
            movimientoTipo: round.isEven ? 'salida' : 'entrada',
            enqueueOutboundStockOps: false,
          );
        });
      }
    }

    for (var i = 1; i <= nProductos; i++) {
      final event = DomainEvent(
        eventId: 'stress:0:$i',
        type: DomainEventType.ajusteInventario,
        aggregateType: 'producto',
        aggregateId: '$i',
        createdBy: 'test',
        payload: {
          'documentType': 'ajuste',
          'documentId': 'stress:0:$i',
          'motivo': 'stress',
          'lines': [
            InventoryLine(productoId: i, cantidad: 1).toJson(),
          ],
        },
      );
      final again = await db.transaction((txn) async {
        return ledger.applyInTxn(
          txn,
          event,
          sign: -1,
          movimientoTipo: 'salida',
          enqueueOutboundStockOps: false,
        );
      });
      expect(again, isFalse, reason: 'doble apply event stress:0:$i');
    }

    final issues = await StockIntegrityValidator.instance.validateAll();
    expect(
      issues,
      isEmpty,
      reason: issues.isEmpty
          ? ''
          : 'divergencias: ${issues.take(5).map((e) => e.toJson()).toList()}',
    );

    final sample = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    expect((sample.first['stock'] as num?)?.toInt(), 1000);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
