import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/producto.dart';
import 'package:sistema_nuevo/models/remito.dart';
import 'package:sistema_nuevo/models/remito_detalle.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/cliente_service.dart';
import 'package:sistema_nuevo/services/producto_service.dart';
import 'package:sistema_nuevo/services/remito_service.dart';

/// Regresión: alta local (producto / venta rápida) no debe colgarse
/// esperando Firestore cuando no hay red (modo avión con sesión nube).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Offline — alta local sin bloquear por sync', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('offline_alta_');
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

    test('crear producto termina en SQLite y encola outbox', () async {
      final sw = Stopwatch()..start();
      final id = await ProductoService().insertar(
        Producto(
          codigo: 'OFF-1',
          descripcion: 'Producto offline',
          marca: '',
          categoria: 'General',
          proveedor: '',
          ubicacion: '',
          stock: 10,
          precio: 100,
          costo: 50,
          observaciones: '',
          foto: '',
        ),
      );
      sw.stop();

      expect(id, greaterThan(0));
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'Alta producto no debe esperar red',
      );

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(rows, isNotEmpty);
      expect(rows.first['codigo'], 'OFF-1');

      final pending = await SyncOutbox.instance.countByStatus(
        SyncOutboxStatus.pending,
      );
      expect(pending, greaterThan(0));
    });

    test('venta rápida (remito + MOSTRADOR) termina local', () async {
      final db = await DatabaseHelper.instance.database;
      final productoId = await db.insert('productos', {
        'codigo': 'VR-1',
        'descripcion': 'Item VR',
        'stock': 20,
        'precio': 500,
        'costo': 200,
      });

      final sw = Stopwatch()..start();
      final mostrador = await ClienteService().obtenerOCrearMostrador();
      final remitoSvc = RemitoService();
      final numero = await remitoSvc.generarNumero();
      final remitoId = await remitoSvc.insertar(
        Remito(
          numero: numero,
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '${mostrador.id}',
          estado: 'confirmado',
          observaciones: 'venta rapida offline',
          total: 1000,
          totalPagado: 1000,
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: productoId,
            cantidad: 2,
            precioUnitario: 500,
            subtotal: 1000,
          ),
        ],
      );
      sw.stop();

      expect(remitoId, greaterThan(0));
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'Venta rápida no debe esperar red',
      );

      final remito = (await db.query(
        'remitos',
        where: 'id = ?',
        whereArgs: [remitoId],
      )).first;
      expect(remito['numero'], numero);
      expect(remito['estado'], 'confirmado');
    });
  });
}
