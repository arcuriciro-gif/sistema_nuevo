import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/remito.dart';
import 'package:sistema_nuevo/models/remito_detalle.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/cuenta_corriente_service.dart';
import 'package:sistema_nuevo/services/remito_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Pagos parciales remito', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('pago_parcial_');
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

    test('estadoDesdeMontos: pendiente / parcial / cobrado', () {
      expect(Remito.estadoDesdeMontos(100, 0), 'pendiente');
      expect(Remito.estadoDesdeMontos(100, 20), 'parcial');
      expect(Remito.estadoDesdeMontos(100, 100), 'cobrado');
    });

    test('pago parcial deja saldo y segundo pago cierra', () async {
      final db = await DatabaseHelper.instance.database;
      final clienteId = await db.insert('clientes', {
        'nombre': 'Cliente Test',
        'saldo': 0,
      });
      final productoId = await db.insert('productos', {
        'codigo': 'P1',
        'descripcion': 'Prod',
        'stock': 50,
        'precio': 1000,
        'costo': 500,
      });

      final remitoSvc = RemitoService();
      final numero = await remitoSvc.generarNumero();
      // Capacidad 8: no permitir remito con cantidad > stock (default).
      final remitoId = await remitoSvc.insertar(
        Remito(
          numero: numero,
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '$clienteId',
          estado: 'confirmado',
          observaciones: '',
          total: 50000,
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: productoId,
            cantidad: 50,
            precioUnitario: 1000,
            subtotal: 50000,
          ),
        ],
      );

      final cc = CuentaCorrienteService();
      await cc.recalcularSaldoCliente(clienteId);
      var cliente = (await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
      )).first;
      expect((cliente['saldo'] as num).toDouble(), closeTo(50000, 0.01));

      await cc.registrarPagoRemito(
        remitoId: remitoId,
        monto: 30000,
        medioPago: 'efectivo',
      );

      final remito = (await db.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [remitoId],
      )).first;
      expect(remito['estadoPago'], 'parcial');
      expect((remito['totalPagado'] as num).toDouble(), closeTo(30000, 0.01));
      expect((remito['saldoPendiente'] as num).toDouble(), closeTo(20000, 0.01));

      cliente = (await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
      )).first;
      expect((cliente['saldo'] as num).toDouble(), closeTo(20000, 0.01));

      await cc.registrarPagoRemito(
        remitoId: remitoId,
        monto: 20000,
        medioPago: 'transferencia',
      );
      final remito2 = (await db.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [remitoId],
      )).first;
      expect(remito2['estadoPago'], 'cobrado');
      expect((remito2['saldoPendiente'] as num).toDouble(), closeTo(0, 0.01));

      cliente = (await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
      )).first;
      expect((cliente['saldo'] as num).toDouble(), closeTo(0, 0.01));
    });
  });
}
