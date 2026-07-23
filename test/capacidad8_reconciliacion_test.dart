import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/event_bus.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/integrity/integrity_policy.dart';
import 'package:sistema_nuevo/core/integrity/integrity_reconcile_service.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 8 — política stock negativo', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await IntegrityPolicy.instance.cargar();
    });

    test('default permite stock negativo (retiro proveedor / venta sin depósito)', () async {
      expect(IntegrityPolicy.instance.permitirStockNegativo, isTrue);
      expect(await IntegrityPolicy.instance.permiteStockResultante(0), isTrue);
      expect(await IntegrityPolicy.instance.permiteStockResultante(-1), isTrue);
    });

    test('si se deshabilita, bloquea resultante negativo', () async {
      await IntegrityPolicy.instance.setPermitirStockNegativo(false);
      expect(await IntegrityPolicy.instance.permiteStockResultante(-3), isFalse);
    });
  });

  group('Capacidad 8 — reconciliación', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await IntegrityPolicy.instance.cargar();
      tmp = await Directory.systemTemp.createTemp('c8_recon_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
      DomainBootstrap.resetForTests();
      DomainBootstrap.ensureInitialized();
      AuthService.instance.currentUser = Usuario(
        id: 1,
        nombre: 'Admin',
        usuario: 'admin',
        password: 'x',
        rol: 'admin',
        activo: true,
        email: 'admin@test.local',
      );
    });

    tearDown(() async {
      DomainBootstrap.resetForTests();
      AuthService.instance.currentUser = null;
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('schema v29 y tablas de integridad', () async {
      expect(DatabaseHelper.schemaVersion, 29);
      final db = await DatabaseHelper.instance.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('integrity_alarms','integrity_scan_meta')",
      );
      expect(tables.length, 2);
    });

    test('assertPuedeAplicar bloquea salida sin stock solo si la política lo prohíbe', () async {
      await IntegrityPolicy.instance.setPermitirStockNegativo(false);
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'C8-1',
        'descripcion': 'Prod',
        'stock': 1,
        'precio': 10,
        'costo': 5,
      });
      await expectLater(
        InventoryLedgerService.instance.assertPuedeAplicar(
          lines: [InventoryLine(productoId: id, cantidad: 5)],
          sign: -1,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('scan detecta proyección de stock rota', () async {
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('productos', {
        'codigo': 'C8-2',
        'descripcion': 'Prod',
        'stock': 10,
        'precio': 10,
        'costo': 5,
      });
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'inv:test:c8:1',
          type: DomainEventType.ajusteInventario,
          payload: {
            'tipo': 'salida',
            'motivo': 'test',
            'lines': [
              InventoryLine(productoId: id, cantidad: 2).toJson(),
            ],
          },
        ),
      );
      // Romper proyección a mano.
      await db.update(
        'productos',
        {'stock': 99},
        where: 'id = ?',
        whereArgs: [id],
      );

      final report = await IntegrityReconcileService.instance.scanAndPersist();
      expect(
        report.alarms.any((a) => a.kind == IntegrityAlarmKind.stockProjection),
        isTrue,
      );
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(id),
        isFalse,
      );
    });

    test('scan detecta saldo CC desalineado vs documentos', () async {
      final db = await DatabaseHelper.instance.database;
      final clienteId = await db.insert('clientes', {
        'nombre': 'Cliente C8',
        'saldo': 500,
      });
      await db.insert('remitos', {
        'numero': 'R-C8-001',
        'clienteId': clienteId,
        'fecha': DateTime.now().toIso8601String(),
        'total': 100,
        'estado': 'pendiente',
        'estadoPago': 'pendiente',
        'totalPagado': 0,
        'saldoPendiente': 100,
      });

      final report = await IntegrityReconcileService.instance.scanAndPersist();
      expect(
        report.alarms.any((a) =>
            a.kind == IntegrityAlarmKind.ccDocument &&
            a.entityId == '$clienteId'),
        isTrue,
      );
    });
  });
}
