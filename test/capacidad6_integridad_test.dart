import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/event_bus.dart';
import 'package:sistema_nuevo/core/domain/money_ledger_service.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Capacidad 6 — contratos', () {
    test('tipos remito CC son estables', () {
      expect(DomainEventType.remitoCargadoCc, 'REMITO_CARGADO_CC');
      expect(DomainEventType.remitoCcRevertido, 'REMITO_CC_REVERTIDO');
      expect(DomainEventType.remitoCobrado, 'REMITO_COBRADO');
      expect(DomainEventType.remitoCobroRevertido, 'REMITO_COBRO_REVERTIDO');
    });
  });

  group('Capacidad 6 — money ledger remitos', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('c6_money_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
      DomainBootstrap.resetForTests();
      DomainBootstrap.ensureInitialized();
    });

    tearDown(() async {
      DomainBootstrap.resetForTests();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('remito cargado + cobrado deja saldo ledger en 0', () async {
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:remito_cc:1',
          type: DomainEventType.remitoCargadoCc,
          payload: {
            'clienteId': 9,
            'remitoId': 1,
            'total': 150.0,
            'motivo': 'test',
          },
        ),
      );
      var saldo =
          await MoneyLedgerService.instance.reconstruirSaldo('cliente_cc', '9');
      expect(saldo, 150.0);

      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:remito_cobrado:1',
          type: DomainEventType.remitoCobrado,
          payload: {
            'clienteId': 9,
            'remitoId': 1,
            'total': 150.0,
            'motivo': 'cobrado',
          },
        ),
      );
      saldo =
          await MoneyLedgerService.instance.reconstruirSaldo('cliente_cc', '9');
      expect(saldo, 0.0);
    });

    test('anular remito pendiente revierte deuda', () async {
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:remito_cc:2',
          type: DomainEventType.remitoCargadoCc,
          payload: {'clienteId': 3, 'remitoId': 2, 'total': 80.0},
        ),
      );
      await DomainEventBus.instance.publish(
        DomainEvent(
          eventId: 'money:remito_cc_rev:2',
          type: DomainEventType.remitoCcRevertido,
          payload: {'clienteId': 3, 'remitoId': 2, 'total': 80.0},
        ),
      );
      final saldo =
          await MoneyLedgerService.instance.reconstruirSaldo('cliente_cc', '3');
      expect(saldo, 0.0);
    });

    test('idempotencia por eventId', () async {
      final ev = DomainEvent(
        eventId: 'money:remito_cc:dup',
        type: DomainEventType.remitoCargadoCc,
        payload: {'clienteId': 1, 'remitoId': 7, 'total': 10.0},
      );
      await DomainEventBus.instance.publish(ev);
      await DomainEventBus.instance.publish(ev);
      final saldo =
          await MoneyLedgerService.instance.reconstruirSaldo('cliente_cc', '1');
      expect(saldo, 10.0);
    });
  });
}
