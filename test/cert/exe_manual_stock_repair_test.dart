import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/sync/windows_sync_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Campo: crash .exe en "Actualizar ahora" + stock divergente residual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('EXE manual refresh hardening 1.4.12', () {
    test('presupuesto quieto prioriza stock y evita clientes masivos', () {
      final b = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      expect(b.stockRounds * b.stockMaxApply, greaterThanOrEqualTo(12));
      expect(b.pullClientes, isFalse);
      expect(b.negocioLimit, lessThanOrEqualTo(10));
      expect(b.stockMicroBatch, lessThanOrEqualTo(b.stockMaxApply));
    });

    test('con cola de productos el presupuesto se reduce (anti-crash)', () {
      final quiet = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 0,
      );
      final busy = WindowsSyncPolicy.manualRefreshBudgetWindows(
        pendingProductos: 100,
      );
      expect(busy.stockMaxApply, lessThanOrEqualTo(quiet.stockMaxApply));
      expect(busy.negocioLimit, lessThanOrEqualTo(quiet.negocioLimit));
      expect(busy.yieldMs, greaterThanOrEqualTo(quiet.yieldMs));
      expect(busy.pullConfig, isFalse);
    });

    test('catch-up Windows ya no omite stock_ops (hardCap anti-crash)', () {
      final c = WindowsSyncPolicy.windowsCatchupStockOpsBudget();
      expect(c.maxPages, greaterThanOrEqualTo(1));
      expect(c.maxApply, greaterThan(0));
      expect(
        c.maxApply,
        lessThanOrEqualTo(WindowsSyncPolicy.stockOpsHardCap),
      );
    });

    test('soft-pull quieto es más rápido que idle cargado', () {
      final quiet = WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 0);
      final busy = WindowsSyncPolicy.softPullIntervalFor(pendingProductos: 80);
      if (WindowsSyncPolicy.freezeBackgroundForStability) {
        // Soft-pull congelado: ambos en 24h (pump no arranca).
        expect(quiet.inHours, greaterThanOrEqualTo(24));
        expect(busy.inHours, greaterThanOrEqualTo(24));
        return;
      }
      expect(quiet.inSeconds, lessThan(busy.inSeconds));
    });
  });

  group('repararProyeccionesDivergentes', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('repair_proj_');
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

    test('corrige stock fantasma tras crash mid-apply', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'REP1',
        'descripcion': 'x',
        'stock': 50,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      await db.transaction((txn) async {
        await InventoryLedgerService.instance.applyInTxn(
          txn,
          DomainEvent(
            eventId: 'adj:rep1',
            type: DomainEventType.ajusteInventario,
            aggregateType: 'producto',
            aggregateId: '$id',
            createdBy: 't',
            payload: {
              'documentType': 'ajuste',
              'documentId': 'rep1',
              'lines': [
                InventoryLine(productoId: id, cantidad: 7).toJson(),
              ],
            },
          ),
          sign: -1,
          movimientoTipo: 'salida',
          enqueueOutboundStockOps: false,
        );
      });
      // Simula crash: proyección corrupta.
      await db.update(
        'productos',
        {'stock': 999},
        where: 'id = ?',
        whereArgs: [id],
      );
      final n =
          await InventoryLedgerService.instance.repararProyeccionesDivergentes(
        limit: 20,
      );
      expect(n, equals(1));
      final row = await db.query(
        'productos',
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.first['stock'], equals(43)); // 50 - 7
    });
  });
}
