import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/integrity/integrity_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/cliente.dart';
import 'package:sistema_nuevo/models/producto.dart';
import 'package:sistema_nuevo/models/remito.dart';
import 'package:sistema_nuevo/models/remito_detalle.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/models/venta.dart';
import 'package:sistema_nuevo/models/venta_item.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/cliente_service.dart';
import 'package:sistema_nuevo/services/cuenta_corriente_service.dart';
import 'package:sistema_nuevo/services/producto_service.dart';
import 'package:sistema_nuevo/services/remito_service.dart';

/// Pruebas adversariales de COMPORTAMIENTO (servicios + SQLite).
/// Tras fixes P0 1.2.34: demuestran correcciones; no asumen “compila ⇒ funciona”.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await IntegrityPolicy.instance.cargar();
    // Tests de venta usan stock suficiente; default ya es no-negativo.
    tmp = await Directory.systemTemp.createTemp('audit_adv_');
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

  Future<int> seedProducto({
    String codigo = 'SKU-1',
    int stock = 10,
    double precio = 100,
    double costo = 40,
  }) {
    return ProductoService().insertar(
      Producto(
        codigo: codigo,
        descripcion: 'Prod $codigo',
        marca: '',
        categoria: 'General',
        proveedor: '',
        ubicacion: '',
        stock: stock,
        precio: precio,
        costo: costo,
        observaciones: '',
        foto: '',
      ),
    );
  }

  Future<int> seedCliente({
    String nombre = 'Cliente Test',
    double limiteCuenta = 0,
    double saldo = 0,
  }) {
    return ClienteService().insertar(
      Cliente(
        nombre: nombre,
        apellido: '',
        telefono: '',
        email: '',
        direccion: '',
        cuit: '',
        observaciones: '',
        saldo: saldo,
        limiteCuenta: limiteCuenta,
      ),
    );
  }

  Future<int> stockDe(int productoId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    return (rows.first['stock'] as num?)?.toInt() ?? -999;
  }

  group('Inventario vs canales de venta', () {
    test('PRODUCIDO: remito SÍ baja stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      await RemitoService().insertar(
        Remito(
          numero: 'R-00001-T',
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '$cid',
          estado: 'confirmado',
          total: 300,
          totalPagado: 300,
          saldoPendiente: 0,
          observaciones: '',
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 3,
            precioUnitario: 100,
            subtotal: 300,
          ),
        ],
      );
      expect(await stockDe(pid), 7);
    });

    test('PRODUCIDO: factura B NO baja stock (política Opción B)', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'factura_b',
          numero: 'B-000001',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 300,
          total: 300,
          totalPagado: 300,
          saldoPendiente: 0,
          observaciones: '',
          estado: 'confirmada',
          estadoPago: 'cobrado',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 3,
            precio: 100,
            subtotal: 300,
          ),
        ],
        montoAbonado: 300,
      );
      // Factura documenta; remito/nota entrega. Stock intacto.
      expect(await stockDe(pid), 10);
    });

    test('PRODUCIDO: presupuesto NO baja stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'presupuesto',
          numero: 'P-000001',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 300,
          total: 300,
          totalPagado: 0,
          saldoPendiente: 300,
          estado: 'confirmada',
          estadoPago: 'pendiente',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 3,
            precio: 100,
            subtotal: 300,
          ),
        ],
      );
      expect(await stockDe(pid), 10);
    });

    test('PRODUCIDO: dos remitos seguidos = doble baja (dos ventas reales)',
        () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final svc = RemitoService();
      for (var i = 1; i <= 2; i++) {
        await svc.insertar(
          Remito(
            numero: 'R-0000$i-T',
            fecha: DateTime.now(),
            tipo: 'salida',
            clienteId: '$cid',
            estado: 'confirmado',
            total: 100,
            totalPagado: 100,
            saldoPendiente: 0,
          observaciones: '',
          ),
          [
            RemitoDetalle(
              remitoId: 0,
              productoId: pid,
              cantidad: 1,
              precioUnitario: 100,
              subtotal: 100,
            ),
          ],
        );
      }
      expect(await stockDe(pid), 8);
    });
  });

  group('Política de stock / validaciones', () {
    test('PRODUCIDO: stock negativo NO permitido por default', () async {
      expect(IntegrityPolicy.instance.permitirStockNegativo, isFalse);
      expect(await IntegrityPolicy.instance.permiteStockResultante(-1), isFalse);
    });

    test('PRODUCIDO: rechaza producto con codigo vacío', () async {
      await expectLater(
        ProductoService().insertar(
          Producto(
            codigo: '  ',
            descripcion: 'Sin código',
            marca: '',
            categoria: '',
            proveedor: '',
            ubicacion: '',
            stock: 0,
            precio: 10,
            costo: 5,
            observaciones: '',
            foto: '',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('PRODUCIDO: rechaza dos productos con el mismo codigo', () async {
      await seedProducto(codigo: 'DUP');
      await expectLater(
        seedProducto(codigo: 'DUP'),
        throwsA(isA<StateError>()),
      );
    });

    test('PRODUCIDO: rechaza costo negativo', () async {
      await expectLater(
        ProductoService().insertar(
          Producto(
            codigo: 'NEG-C',
            descripcion: 'Costo malo',
            marca: '',
            categoria: '',
            proveedor: '',
            ubicacion: '',
            stock: 0,
            precio: 10,
            costo: -5,
            observaciones: '',
            foto: '',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('PRODUCIDO: rechaza precio negativo', () async {
      await expectLater(
        ProductoService().insertar(
          Producto(
            codigo: 'NEG-P',
            descripcion: 'Precio malo',
            marca: '',
            categoria: '',
            proveedor: '',
            ubicacion: '',
            stock: 0,
            precio: -50,
            costo: 10,
            observaciones: '',
            foto: '',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Cuenta corriente', () {
    test('PRODUCIDO: limiteCuenta bloquea venta a CC', () async {
      final pid = await seedProducto(stock: 10, precio: 1000);
      final cid = await seedCliente(limiteCuenta: 100);
      await expectLater(
        RemitoService().insertar(
          Remito(
            numero: 'R-CC-001-T',
            fecha: DateTime.now(),
            tipo: 'salida',
            clienteId: '$cid',
            estado: 'confirmado',
            total: 1000,
            totalPagado: 0,
            saldoPendiente: 1000,
          observaciones: '',
          ),
          [
            RemitoDetalle(
              remitoId: 0,
              productoId: pid,
              cantidad: 1,
              precioUnitario: 1000,
              subtotal: 1000,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
      expect(await stockDe(pid), 10);
    });

    test('PRODUCIDO: actualizar cliente NO pisa saldo a mano', () async {
      final cid = await seedCliente(saldo: 50);
      final db = await DatabaseHelper.instance.database;
      final actual = Cliente.fromMap(
        (await db.query('clientes', where: 'id=?', whereArgs: [cid], limit: 1))
            .first,
      );
      await ClienteService().actualizar(
        actual.copyWith(saldo: 1234, telefono: '111'),
      );
      final despues = Cliente.fromMap(
        (await db.query('clientes', where: 'id=?', whereArgs: [cid], limit: 1))
            .first,
      );
      expect(despues.saldo, 50);
      expect(despues.telefono, '111');
    });
  });

  group('Hard-delete producto', () {
    test('PRODUCIDO: eliminarDefinitivo encola tombstone delete', () async {
      final pid = await seedProducto(codigo: 'DEL-1');
      await ProductoService().eliminarDefinitivo(pid);
      final db = await DatabaseHelper.instance.database;
      final local = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [pid],
      );
      expect(local, isEmpty);
      final outbox = await db.query(
        'sync_outbox',
        where: "op_id = ?",
        whereArgs: ['delete:producto:DEL-1'],
      );
      expect(outbox, isNotEmpty);
      expect(outbox.first['operation']?.toString(), 'delete');
    });
  });
}
