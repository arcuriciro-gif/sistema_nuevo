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
/// Demuestran fallos reales; no asumen que “compila ⇒ funciona”.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
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
    double limite = 0,
    double saldo = 0,
  }) {
    return ClienteService().insertar(
      Cliente(
        nombre: nombre,
        telefono: '111',
        direccion: 'Calle 1',
        observaciones: '',
        limiteCuenta: limite,
        saldo: saldo,
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
    return (rows.first['stock'] as num).toInt();
  }

  Remito remitoSalida({
    required String numero,
    required int clienteId,
    required double total,
    String estadoPago = 'cobrado',
    double? pagado,
  }) {
    final p = pagado ?? (estadoPago == 'cobrado' ? total : 0);
    return Remito(
      numero: numero,
      fecha: DateTime.now(),
      tipo: 'salida',
      clienteId: '$clienteId',
      estado: 'confirmado',
      estadoPago: estadoPago,
      totalPagado: p,
      saldoPendiente: total - p,
      observaciones: 'audit',
      total: total,
    );
  }

  group('Inventario vs canales de venta', () {
    test('PRODUCIDO: remito SÍ baja stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      await RemitoService().insertar(
        remitoSalida(numero: 'R-ADV-1', clienteId: cid, total: 200),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 2,
            precioUnitario: 100,
            subtotal: 200,
            costoUnitario: 40,
          ),
        ],
        medioPago: 'efectivo',
      );
      expect(await stockDe(pid), 8);
    });

    test('PRODUCIDO: factura B NO baja stock (bug ERP)', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'factura_b',
          numero: 'B-ADV-1',
          clienteId: cid,
          clienteNombre: 'Cliente Test',
          fecha: DateTime.now(),
          subtotal: 300,
          total: 300,
          estado: 'confirmada',
          estadoPago: 'cobrado',
          totalPagado: 300,
          saldoPendiente: 0,
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 3,
            precio: 100,
            subtotal: 300,
            costoUnitario: 40,
          ),
        ],
        montoAbonado: 300,
        medioPago: 'efectivo',
      );
      expect(
        await stockDe(pid),
        10,
        reason:
            'Comportamiento actual (bug): factura no toca inventario. '
            'Si este expect falla, el bug fue corregido.',
      );
    });

    test('PRODUCIDO: dos remitos seguidos = doble baja (double-submit servicio)',
        () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final items = [
        RemitoDetalle(
          remitoId: 0,
          productoId: pid,
          cantidad: 1,
          precioUnitario: 100,
          subtotal: 100,
          costoUnitario: 40,
        ),
      ];
      await RemitoService().insertar(
        remitoSalida(numero: 'R-DUP-1', clienteId: cid, total: 100),
        items,
        medioPago: 'efectivo',
      );
      await RemitoService().insertar(
        remitoSalida(numero: 'R-DUP-2', clienteId: cid, total: 100),
        items,
        medioPago: 'efectivo',
      );
      expect(await stockDe(pid), 8);
      final db = await DatabaseHelper.instance.database;
      final n = await db.rawQuery('SELECT COUNT(*) c FROM remitos');
      expect((n.first['c'] as num).toInt(), 2);
    });
  });

  group('Política de stock / validaciones', () {
    test('PRODUCIDO: stock negativo permitido por default', () async {
      await IntegrityPolicy.instance.cargar();
      expect(IntegrityPolicy.instance.permitirStockNegativo, isTrue);

      final pid = await seedProducto(stock: 1);
      final cid = await seedCliente();
      await RemitoService().insertar(
        remitoSalida(numero: 'R-NEG-1', clienteId: cid, total: 500),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 5,
            precioUnitario: 100,
            subtotal: 500,
            costoUnitario: 40,
          ),
        ],
        medioPago: 'efectivo',
      );
      expect(await stockDe(pid), -4);
    });

    test('PRODUCIDO: permite producto con codigo vacío', () async {
      final id = await ProductoService().insertar(
        Producto(
          codigo: '',
          descripcion: 'Sin codigo',
          marca: '',
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 1,
          precio: 10,
          costo: 1,
          observaciones: '',
          foto: '',
        ),
      );
      expect(id, greaterThan(0));
      final db = await DatabaseHelper.instance.database;
      final rows =
          await db.query('productos', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['codigo'], '');
    });

    test('PRODUCIDO: permite dos productos con el mismo codigo', () async {
      await seedProducto(codigo: 'DUP');
      await seedProducto(codigo: 'DUP');
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'productos',
        where: 'codigo = ?',
        whereArgs: ['DUP'],
      );
      expect(rows.length, 2);
    });

    test(
        'PRODUCIDO: insertar no rechaza precio negativo; calculador lo sobrescribe',
        () async {
      // El service NO valida; recalcula listas desde costo → precio != -50.
      await ProductoService().insertar(
        Producto(
          codigo: 'NEG-P',
          descripcion: 'Precio negativo',
          marca: '',
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 1,
          precio: -50,
          costo: 10,
          observaciones: '',
          foto: '',
        ),
      );
      final p = await ProductoService().buscarPorCodigo('NEG-P');
      expect(p, isNotNull);
      expect(p!.precio, isNot(equals(-50)));
      expect(p.precio, greaterThan(0));
    });

    test('PRODUCIDO: permite costo negativo (sin validación de dominio)',
        () async {
      await ProductoService().insertar(
        Producto(
          codigo: 'NEG-C',
          descripcion: 'Costo negativo',
          marca: '',
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 1,
          precio: 10,
          costo: -5,
          observaciones: '',
          foto: '',
        ),
      );
      final p = await ProductoService().buscarPorCodigo('NEG-C');
      expect(p!.costo, -5);
    });
  });

  group('Cuenta corriente', () {
    test('PRODUCIDO: limiteCuenta no bloquea venta a CC', () async {
      final pid = await seedProducto(stock: 100, precio: 1000);
      final cid = await seedCliente(limite: 100);
      await RemitoService().insertar(
        remitoSalida(
          numero: 'R-LIM-1',
          clienteId: cid,
          total: 1000,
          estadoPago: 'pendiente',
          pagado: 0,
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 1,
            precioUnitario: 1000,
            subtotal: 1000,
            costoUnitario: 40,
          ),
        ],
        medioPago: 'cuenta_corriente',
      );
      await CuentaCorrienteService().recalcularSaldoCliente(cid);
      final db = await DatabaseHelper.instance.database;
      final c = await db.query('clientes', where: 'id = ?', whereArgs: [cid]);
      final saldo = (c.first['saldo'] as num).toDouble();
      expect(saldo, greaterThan(100));
    });

    test('PRODUCIDO: actualizar cliente puede pisar saldo a mano', () async {
      final cid = await seedCliente(saldo: 0);
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'clientes',
        {'saldo': 9999},
        where: 'id = ?',
        whereArgs: [cid],
      );
      // El servicio de actualización también acepta saldo del modelo:
      final cli = (await ClienteService().obtenerTodos())
          .firstWhere((e) => e.id == cid);
      expect(cli.saldo, 9999);
      await ClienteService().actualizar(
        Cliente(
          id: cli.id,
          syncId: cli.syncId,
          nombre: cli.nombre,
          telefono: cli.telefono,
          direccion: cli.direccion,
          observaciones: cli.observaciones,
          saldo: 1234,
          limiteCuenta: cli.limiteCuenta,
        ),
      );
      final c = await db.query('clientes', where: 'id = ?', whereArgs: [cid]);
      expect((c.first['saldo'] as num).toDouble(), 1234);
    });
  });

  group('Hard-delete producto', () {
    test(
        'PRODUCIDO: eliminarDefinitivo borra local y no encola tombstone delete',
        () async {
      final pid = await seedProducto(codigo: 'DEL-1');
      await ProductoService().eliminar(pid);
      await ProductoService().eliminarDefinitivo(pid);
      final db = await DatabaseHelper.instance.database;
      final gone =
          await db.query('productos', where: 'id = ?', whereArgs: [pid]);
      expect(gone, isEmpty);
      final deletes = await db.query(
        'sync_outbox',
        where: "entity_type = ? AND operation = ?",
        whereArgs: ['producto', 'delete'],
      );
      expect(
        deletes,
        isEmpty,
        reason: 'Sin tombstone outbox el peer puede revivir el SKU',
      );
    });
  });
}
