import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_bootstrap.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/integrity/integrity_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/models/cliente.dart';
import 'package:sistema_nuevo/models/compra.dart';
import 'package:sistema_nuevo/models/compra_detalle.dart';
import 'package:sistema_nuevo/models/movimiento_stock.dart';
import 'package:sistema_nuevo/models/producto.dart';
import 'package:sistema_nuevo/models/remito.dart';
import 'package:sistema_nuevo/models/remito_detalle.dart';
import 'package:sistema_nuevo/models/usuario.dart';
import 'package:sistema_nuevo/models/venta.dart';
import 'package:sistema_nuevo/models/venta_item.dart';
import 'package:sistema_nuevo/services/auth_service.dart';
import 'package:sistema_nuevo/services/cliente_service.dart';
import 'package:sistema_nuevo/services/compra_service.dart';
import 'package:sistema_nuevo/services/cuenta_corriente_service.dart';
import 'package:sistema_nuevo/services/producto_service.dart';
import 'package:sistema_nuevo/services/remito_service.dart';
import 'package:sistema_nuevo/services/stock_service.dart';
import 'package:sistema_nuevo/services/venta_service.dart';

/// Matriz de integridad inventario / CC (Sprint P0 motor).
/// Cada caso documenta: stock esperado, ledger, CC, resultado.
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
    tmp = await Directory.systemTemp.createTemp('matriz_inv_');
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

  Future<int> seedProducto({String codigo = 'SKU-1', int stock = 10}) {
    return ProductoService().insertar(
      Producto(
        codigo: codigo,
        descripcion: 'Prod $codigo',
        marca: '',
        categoria: 'General',
        proveedor: '',
        ubicacion: '',
        stock: stock,
        precio: 100,
        costo: 40,
        observaciones: '',
        foto: '',
      ),
    );
  }

  Future<int> seedCliente({double limiteCuenta = 0}) {
    return ClienteService().insertar(
      Cliente(
        nombre: 'Cliente Test',
        apellido: '',
        telefono: '',
        email: '',
        direccion: '',
        cuit: '',
        observaciones: '',
        saldo: 0,
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

  Future<int> ledgerCount(int productoId) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM inventory_ledger WHERE product_id = ?',
      [productoId],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> ledgerSum(int productoId) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(delta),0) s FROM inventory_ledger WHERE product_id = ?',
      [productoId],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  Future<double> saldoCliente(int clienteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'clientes',
      columns: ['saldo'],
      where: 'id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );
    return (rows.first['saldo'] as num?)?.toDouble() ?? -999;
  }

  group('R3 política Opción B — remito entrega / factura documenta', () {
    test('remito baja stock; factura B no; juntos no doble-descuentan', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();

      await RemitoService().insertar(
        Remito(
          numero: 'R-MAT-001-T',
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '$cid',
          estado: 'confirmado',
          total: 200,
          totalPagado: 200,
          saldoPendiente: 0,
          observaciones: '',
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 2,
            precioUnitario: 100,
            subtotal: 200,
          ),
        ],
      );
      expect(await stockDe(pid), 8);

      await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'factura_b',
          numero: 'B-MAT-001',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 200,
          total: 200,
          totalPagado: 200,
          saldoPendiente: 0,
          estado: 'confirmada',
          estadoPago: 'cobrado',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 2,
            precio: 100,
            subtotal: 200,
          ),
        ],
        montoAbonado: 200,
      );
      // Stock sigue en 8 (solo remito entregó).
      expect(await stockDe(pid), 8);
      expect(await ledgerSum(pid), 8); // +10 alta -2 remito
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(pid),
        isTrue,
      );
    });
  });

  group('R1 anular/eliminar venta con entrega', () {
    test('nota_entrega: crear → anular restaura stock + ledger rev', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final vid = await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'nota_entrega',
          numero: 'NE-000001',
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
      expect(await stockDe(pid), 7);
      expect(await saldoCliente(cid), closeTo(300, 0.01));

      await VentaService().anular(vid);
      expect(await stockDe(pid), 10);
      expect(await saldoCliente(cid), closeTo(0, 0.01));
      expect(await ledgerSum(pid), 10); // +10 -3 +3
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(pid),
        isTrue,
      );
    });

    test('eliminar nota_entrega anula primero y restaura stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final vid = await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'nota_entrega',
          numero: 'NE-000002',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 200,
          total: 200,
          totalPagado: 0,
          saldoPendiente: 200,
          estado: 'confirmada',
          estadoPago: 'pendiente',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 2,
            precio: 100,
            subtotal: 200,
          ),
        ],
      );
      expect(await stockDe(pid), 8);
      await VentaService().eliminar(vid);
      expect(await stockDe(pid), 10);
      final db = await DatabaseHelper.instance.database;
      final venta = await db.query('ventas', where: 'id=?', whereArgs: [vid]);
      expect(venta, isEmpty);
    });

    test('anular factura B no mueve stock (nunca entregó)', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final vid = await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'factura_b',
          numero: 'B-MAT-ANUL',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 100,
          total: 100,
          totalPagado: 0,
          saldoPendiente: 100,
          estado: 'confirmada',
          estadoPago: 'pendiente',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 1,
            precio: 100,
            subtotal: 100,
          ),
        ],
      );
      final ledgerAntes = await ledgerCount(pid);
      await VentaService().anular(vid);
      expect(await stockDe(pid), 10);
      expect(await ledgerCount(pid), ledgerAntes); // sin movimientos extra
      expect(await saldoCliente(cid), closeTo(0, 0.01));
    });
  });

  group('R1 remito anular/eliminar', () {
    test('anular remito restaura stock exacto', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final rid = await RemitoService().insertar(
        Remito(
          numero: 'R-ANUL-1-T',
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '$cid',
          estado: 'confirmado',
          total: 400,
          totalPagado: 400,
          saldoPendiente: 0,
          observaciones: '',
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 4,
            precioUnitario: 100,
            subtotal: 400,
          ),
        ],
      );
      expect(await stockDe(pid), 6);
      await RemitoService().anular(rid);
      expect(await stockDe(pid), 10);
      expect(await ledgerSum(pid), 10);
    });

    test('eliminar remito anula y restaura', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final rid = await RemitoService().insertar(
        Remito(
          numero: 'R-DEL-1-T',
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
      await RemitoService().eliminar(rid);
      expect(await stockDe(pid), 10);
    });
  });

  group('R2 compras create/edit/anular', () {
    test('crear compra suma stock via ledger', () async {
      final pid = await seedProducto(stock: 5);
      final cid = await CompraService().insertar(
        Compra(
          proveedorId: null,
          proveedorNombre: 'Prov',
          numero: 'C-00001-T',
          factura: '',
          fecha: DateTime.now(),
          total: 200,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 3,
            costo: 40,
            subtotal: 120,
          ),
        ],
      );
      expect(cid, isPositive);
      expect(await stockDe(pid), 8);
      expect(await ledgerSum(pid), 8);
    });

    test('editar compra recalcula (no suma sobre movimiento viejo)', () async {
      final pid = await seedProducto(stock: 0);
      final svc = CompraService();
      final id = await svc.insertar(
        Compra(
          proveedorId: null,
          proveedorNombre: 'Prov',
          numero: 'C-00002-T',
          factura: '',
          fecha: DateTime.now(),
          total: 200,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 5,
            costo: 40,
            subtotal: 200,
          ),
        ],
      );
      expect(await stockDe(pid), 5);

      await svc.actualizar(
        id,
        Compra(
          id: id,
          proveedorId: null,
          proveedorNombre: 'Prov',
          numero: 'C-00002-T',
          factura: '',
          fecha: DateTime.now(),
          total: 80,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: id,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 2,
            costo: 40,
            subtotal: 80,
          ),
        ],
      );
      expect(await stockDe(pid), 2);
      // +0alta? seed 0 +5 -5 +2 = 2
      expect(await ledgerSum(pid), 2);

      // Segunda edición: eventIds con $rev distintos → no skip idempotente.
      await svc.actualizar(
        id,
        Compra(
          id: id,
          proveedorId: null,
          proveedorNombre: 'Prov2',
          numero: 'C-00002-T',
          factura: '',
          fecha: DateTime.now(),
          total: 120,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: id,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 3,
            costo: 40,
            subtotal: 120,
          ),
        ],
      );
      expect(await stockDe(pid), 3);
      expect(await ledgerSum(pid), 3);
    });

    test('anular compra revierte recepción', () async {
      final pid = await seedProducto(stock: 2);
      final svc = CompraService();
      final id = await svc.insertar(
        Compra(
          proveedorId: null,
          proveedorNombre: 'Prov',
          numero: 'C-00003-T',
          factura: '',
          fecha: DateTime.now(),
          total: 400,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 4,
            costo: 40,
            subtotal: 160,
          ),
        ],
      );
      expect(await stockDe(pid), 6);
      await svc.anular(id);
      expect(await stockDe(pid), 2);
    });
  });

  group('R4/R5 stock solo vía ledger / import', () {
    test('alta producto con stock genera movimiento, no write absoluto', () async {
      final pid = await seedProducto(codigo: 'ALT-1', stock: 15);
      expect(await stockDe(pid), 15);
      expect(await ledgerCount(pid), greaterThanOrEqualTo(1));
      expect(await ledgerSum(pid), 15);
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(pid),
        isTrue,
      );
    });

    test('editar stock del producto se convierte en ajuste', () async {
      final pid = await seedProducto(codigo: 'EDIT-S', stock: 10);
      final p = (await ProductoService().buscarPorCodigo('EDIT-S'))!;
      await ProductoService().actualizar(p.copyWith(stock: 13));
      expect(await stockDe(pid), 13);
      expect(await ledgerSum(pid), 13);
      final db = await DatabaseHelper.instance.database;
      final ajustes = await db.query(
        'inventory_ledger',
        where: "product_id = ? AND reason LIKE '%edición%'",
        whereArgs: [pid],
      );
      expect(ajustes, isNotEmpty);
      expect(ajustes.last['delta'], 3);
    });

    test('insertarLista importa stock via ledger', () async {
      await ProductoService().insertarLista([
        Producto(
          codigo: 'IMP-1',
          descripcion: 'Importado',
          marca: '',
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 7,
          precio: 50,
          costo: 20,
          observaciones: '',
          foto: '',
        ),
      ]);
      final p = await ProductoService().buscarPorCodigo('IMP-1');
      expect(p, isNotNull);
      expect(await stockDe(p!.id!), 7);
      expect(await ledgerSum(p.id!), 7);
    });

    test('ajuste manual StockService genera ledger', () async {
      final pid = await seedProducto(stock: 10);
      await StockService().registrarMovimiento(
        MovimientoStock(
          productoId: pid,
          tipo: 'salida',
          cantidad: 2,
          fecha: DateTime.now(),
          motivo: 'Corrección inventario',
          usuario: 'admin',
        ),
      );
      expect(await stockDe(pid), 8);
      expect(await ledgerSum(pid), 8);
    });
  });

  group('R1 restaurar venta / R2 reabrir compra', () {
    test('anular→restaurar→anular nota_entrega restaura stock exacto', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final vid = await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'nota_entrega',
          numero: 'NE-REST-1',
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
      final svc = VentaService();
      expect(await stockDe(pid), 7);
      expect(await saldoCliente(cid), closeTo(300, 0.01));

      await svc.anular(vid);
      expect(await stockDe(pid), 10);
      expect(await saldoCliente(cid), closeTo(0, 0.01));

      await svc.restaurar(vid);
      expect(await stockDe(pid), 7);
      expect(await saldoCliente(cid), closeTo(300, 0.01));

      await svc.anular(vid);
      expect(await stockDe(pid), 10);
      expect(await saldoCliente(cid), closeTo(0, 0.01));
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(pid),
        isTrue,
      );
    });

    test('restaurar factura B no mueve stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final vid = await CuentaCorrienteService().crearVentaConPago(
        venta: Venta(
          tipo: 'factura_b',
          numero: 'B-REST-1',
          clienteId: cid,
          fecha: DateTime.now(),
          subtotal: 100,
          total: 100,
          totalPagado: 0,
          saldoPendiente: 100,
          estado: 'confirmada',
          estadoPago: 'pendiente',
        ),
        items: [
          VentaItem(
            ventaId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 1,
            precio: 100,
            subtotal: 100,
          ),
        ],
      );
      final svc = VentaService();
      await svc.anular(vid);
      await svc.restaurar(vid);
      expect(await stockDe(pid), 10);
      expect(await saldoCliente(cid), closeTo(100, 0.01));
    });

    test('compra anular→reabrir→anular sin doble suma', () async {
      final pid = await seedProducto(stock: 5);
      final svc = CompraService();
      final id = await svc.insertar(
        Compra(
          proveedorId: null,
          proveedorNombre: 'Prov',
          numero: 'C-REOPEN-1-T',
          factura: '',
          fecha: DateTime.now(),
          total: 200,
          descuento: 0,
          iva: 0,
          observaciones: '',
          estado: 'confirmada',
        ),
        [
          CompraDetalle(
            compraId: 0,
            productoId: pid,
            productoDescripcion: 'Prod',
            cantidad: 4,
            costo: 40,
            subtotal: 160,
          ),
        ],
      );
      expect(await stockDe(pid), 9);
      await svc.anular(id);
      expect(await stockDe(pid), 5);
      await svc.reabrir(id);
      expect(await stockDe(pid), 9);
      await svc.anular(id);
      expect(await stockDe(pid), 5);
      expect(await ledgerSum(pid), 5);
    });
  });

  group('Remito restaurar / cobro cycles', () {
    test('remito anular→restaurar→anular sin doble movimiento', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final rid = await RemitoService().insertar(
        Remito(
          numero: 'R-REST-1-T',
          fecha: DateTime.now(),
          tipo: 'salida',
          clienteId: '$cid',
          estado: 'confirmado',
          total: 200,
          totalPagado: 0,
          saldoPendiente: 200,
          observaciones: '',
        ),
        [
          RemitoDetalle(
            remitoId: 0,
            productoId: pid,
            cantidad: 2,
            precioUnitario: 100,
            subtotal: 200,
          ),
        ],
      );
      final svc = RemitoService();
      expect(await stockDe(pid), 8);
      await svc.anular(rid);
      expect(await stockDe(pid), 10);
      await svc.restaurar(rid);
      expect(await stockDe(pid), 8);
      await svc.anular(rid);
      expect(await stockDe(pid), 10);
      expect(
        await InventoryLedgerService.instance.verificarProyeccion(pid),
        isTrue,
      );
    });
  });

  group('Sync stock_op inbound', () {
    test('applyRemoteStockOp es idempotente y no duplica', () async {
      final pid = await seedProducto(codigo: 'SYNC-1', stock: 10);
      final ok1 = await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'inv:entrega:remito:99_1',
        productoId: pid,
        codigo: 'SYNC-1',
        delta: -3,
      );
      final ok2 = await InventoryLedgerService.instance.applyRemoteStockOp(
        opId: 'inv:entrega:remito:99_1',
        productoId: pid,
        codigo: 'SYNC-1',
        delta: -3,
      );
      expect(ok1, isTrue);
      expect(ok2, isFalse);
      expect(await stockDe(pid), 7);
      expect(await ledgerSum(pid), 7);
    });

    test('applyRemoteStockOpsBatch aplica varias en una TX', () async {
      final pid = await seedProducto(codigo: 'SYNC-B', stock: 20);
      final n = await InventoryLedgerService.instance.applyRemoteStockOpsBatch([
        (
          opId: 'op:batch:a',
          productoId: pid,
          codigo: 'SYNC-B',
          delta: -2,
        ),
        (
          opId: 'op:batch:b',
          productoId: pid,
          codigo: 'SYNC-B',
          delta: -3,
        ),
        (
          opId: 'op:batch:a', // idempotente
          productoId: pid,
          codigo: 'SYNC-B',
          delta: -2,
        ),
      ]);
      expect(n, 2);
      expect(await stockDe(pid), 15);
    });
  });

  group('R4 metadata no pisa stock', () {
    test('toggleFavorito no clobber stock tras movimiento', () async {
      final pid = await seedProducto(codigo: 'FAV-1', stock: 10);
      await StockService().registrarMovimiento(
        MovimientoStock(
          productoId: pid,
          tipo: 'salida',
          cantidad: 3,
          fecha: DateTime.now(),
          motivo: 'ajuste',
          usuario: 'admin',
        ),
      );
      expect(await stockDe(pid), 7);
      // Snapshot "viejo" con stock 10 — no debe pisar proyección.
      final stale = Producto(
        id: pid,
        codigo: 'FAV-1',
        descripcion: 'Prod FAV-1',
        marca: '',
        categoria: 'General',
        proveedor: '',
        ubicacion: '',
        stock: 10,
        precio: 100,
        costo: 40,
        observaciones: '',
        foto: '',
      );
      await ProductoService().toggleFavorito(stale);
      expect(await stockDe(pid), 7);
    });
  });

  group('Idempotencia / proyección', () {
    test('doble anular remito no duplica stock', () async {
      final pid = await seedProducto(stock: 10);
      final cid = await seedCliente();
      final rid = await RemitoService().insertar(
        Remito(
          numero: 'R-IDEM-1-T',
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
      await RemitoService().anular(rid);
      await RemitoService().anular(rid);
      expect(await stockDe(pid), 10);
    });
  });
}
