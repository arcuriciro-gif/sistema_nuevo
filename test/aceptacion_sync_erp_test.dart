import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/sync/remote_line_product_resolve.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_hold_store.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Aceptación Tata.Manager — sync ERP Windows ↔ APK (sin Firebase).
///
/// Simula dos nodos con DBs temporales separadas. Los payloads Firestore
/// se representan como `Map<String, dynamic>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmpWin;
  late Directory tmpApk;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpWin = await Directory.systemTemp.createTemp('acept_win_');
    tmpApk = await Directory.systemTemp.createTemp('acept_apk_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrar();
    try {
      await tmpWin.delete(recursive: true);
    } catch (_) {}
    try {
      await tmpApk.delete(recursive: true);
    } catch (_) {}
  });

  Future<Database> openNode(Directory dir, {String name = 't.db'}) async {
    await DatabaseHelper.instance.cerrar();
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(dir.path, name),
    );
    return DatabaseHelper.instance.database;
  }

  Future<int> count(Database db, String table, {String? where}) async {
    final sql = where == null
        ? 'SELECT COUNT(*) FROM $table'
        : 'SELECT COUNT(*) FROM $table WHERE $where';
    return Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;
  }

  Future<int> stockOf(Database db, int id) async {
    final rows = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return (rows.first['stock'] as num).toInt();
  }

  Future<Map<String, dynamic>> productoByCodigo(
    Database db,
    String codigo,
  ) async {
    final rows = await db.query(
      'productos',
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    expect(rows, isNotEmpty, reason: 'producto $codigo debe existir');
    return Map<String, dynamic>.from(rows.first);
  }

  /// Inserta fillers para forzar autoincrement distinto al peer.
  Future<void> seedAutoincrementOffset(Database db, int n) async {
    for (var i = 0; i < n; i++) {
      await db.insert('productos', {
        'codigo': '__pad_$i',
        'descripcion': 'pad',
        'stock': 0,
        'precio': 0,
        'costo': 0,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Aplica un producto remoto (Firestore map) por codigo.
  Future<int> applyProductoFromRemote(
    Database db,
    Map<String, dynamic> remote,
  ) async {
    final codigo = remote['codigo'] as String;
    final existing = await db.query(
      'productos',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    final fields = <String, Object?>{
      'codigo': codigo,
      'descripcion': remote['descripcion'] ?? codigo,
      'precio': remote['precio'] ?? 0,
      'costo': remote['costo'] ?? 0,
      'marca': remote['marca'] ?? '',
      'categoria': remote['categoria'] ?? '',
      'proveedor': remote['proveedor'] ?? '',
      'ubicacion': remote['ubicacion'] ?? '',
      'actualizadoEn':
          remote['actualizadoEn'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    if (remote.containsKey('stock')) {
      fields['stock'] = remote['stock'];
    }
    if (existing.isEmpty) {
      fields.putIfAbsent('stock', () => 0);
      return db.insert('productos', fields);
    }
    final id = existing.first['id'] as int;
    await db.update('productos', fields, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Map<String, dynamic> productToUploadMap(Map<String, dynamic> row) {
    return {
      'codigo': row['codigo'],
      'descripcion': row['descripcion'],
      'precio': row['precio'],
      'costo': row['costo'],
      'marca': row['marca'] ?? '',
      'categoria': row['categoria'] ?? '',
      'stock': 0,
      'actualizadoEn': row['actualizadoEn'],
    };
  }

  test('PRAGMA foreign_keys = 1 en ambos nodos', () async {
    final win = await openNode(tmpWin);
    expect(
      Sqflite.firstIntValue(await win.rawQuery('PRAGMA foreign_keys')),
      1,
    );

    final apk = await openNode(tmpApk);
    expect(
      Sqflite.firstIntValue(await apk.rawQuery('PRAGMA foreign_keys')),
      1,
    );
  });

  test(
      '1) producto create/modify converge por codigo (ids autoincrement distintos)',
      () async {
    final win = await openNode(tmpWin);
    final idWin = await win.insert('productos', {
      'codigo': 'SKU-ACEPT-1',
      'descripcion': 'Original',
      'stock': 5,
      'precio': 100,
      'costo': 40,
      'marca': 'MarcaA',
      'categoria': 'Cat',
      'actualizadoEn': '2026-07-01T00:00:00.000Z',
    });
    await win.update(
      'productos',
      {
        'descripcion': 'Modificado Win',
        'precio': 120,
        'actualizadoEn': '2026-07-02T00:00:00.000Z',
      },
      where: 'id = ?',
      whereArgs: [idWin],
    );
    final winRow = await productoByCodigo(win, 'SKU-ACEPT-1');
    final upload = productToUploadMap(winRow)
      ..['descripcion'] = winRow['descripcion']
      ..['precio'] = winRow['precio'];

    final apk = await openNode(tmpApk);
    await seedAutoincrementOffset(apk, 7);
    final idApkSeed = await apk.insert('productos', {
      'codigo': 'SKU-ACEPT-1',
      'descripcion': 'Viejo APK',
      'stock': 0,
      'precio': 50,
      'costo': 40,
      'actualizadoEn': '2026-06-01T00:00:00.000Z',
    });
    final idApk = await applyProductoFromRemote(apk, upload);
    expect(idApk, idApkSeed);
    expect(idApk, isNot(idWin),
        reason: 'autoincrement local distinto; sync es por codigo');

    final apkRow = await productoByCodigo(apk, 'SKU-ACEPT-1');
    expect(apkRow['descripcion'], 'Modificado Win');
    expect((apkRow['precio'] as num).toDouble(), 120);
    expect(apkRow['codigo'], winRow['codigo']);
    expect(apkRow['costo'], winRow['costo']);
  });

  test('2) producto stock==0 visible en ambos (conteo WHERE stock=0 igual)',
      () async {
    final win = await openNode(tmpWin);
    for (final codigo in ['P-ZERO-A', 'P-ZERO-B', 'P-ZERO-C']) {
      await win.insert('productos', {
        'codigo': codigo,
        'descripcion': codigo,
        'stock': 0,
        'precio': 1,
        'costo': 0,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
    }
    final zeroWin = await count(win, 'productos', where: 'stock = 0');
    expect(zeroWin, 3);

    final uploads = [
      for (final c in ['P-ZERO-A', 'P-ZERO-B', 'P-ZERO-C'])
        {
          'codigo': c,
          'descripcion': c,
          'stock': 0,
          'precio': 1,
          'costo': 0,
        },
    ];

    final apk = await openNode(tmpApk);
    for (final u in uploads) {
      await applyProductoFromRemote(apk, u);
    }
    final zeroApk = await count(apk, 'productos', where: 'stock = 0');
    expect(zeroApk, zeroWin);
    expect(zeroApk, 3);
  });

  test(
      '3) remito con peer productoId distinto resuelve por codigo; FK ON; mismos conteos',
      () async {
    final win = await openNode(tmpWin);
    final prodWin = await win.insert('productos', {
      'codigo': 'SKU-REM',
      'descripcion': 'item remito',
      'stock': 10,
      'precio': 50,
      'costo': 20,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final remWin = await win.insert('remitos', {
      'numero': 'R-ACEPT-3',
      'fecha': DateTime.now().toIso8601String(),
      'total': 50,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 50,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    await win.insert('remito_items', {
      'remitoId': remWin,
      'productoId': prodWin,
      'cantidad': 1,
      'precio': 50,
      'subtotal': 50,
      'costoUnitario': 20,
      'ganancia': 30,
    });
    final remitosWin = await count(win, 'remitos');
    final itemsWin = await count(win, 'remito_items');

    final firestoreRemito = {
      'numero': 'R-ACEPT-3',
      'fecha': DateTime.now().toIso8601String(),
      'total': 50,
      'items': [
        {
          'productoId': prodWin,
          'productoCodigo': 'SKU-REM',
          'cantidad': 1,
          'precio': 50,
          'subtotal': 50,
        },
      ],
    };

    final apk = await openNode(tmpApk);
    expect(
      Sqflite.firstIntValue(await apk.rawQuery('PRAGMA foreign_keys')),
      1,
    );

    await seedAutoincrementOffset(apk, 5);
    final prodApk = await applyProductoFromRemote(apk, {
      'codigo': 'SKU-REM',
      'descripcion': 'item remito',
      'stock': 0,
      'precio': 50,
      'costo': 20,
    });
    expect(prodApk, isNot(prodWin));

    final localByCodigo = {'SKU-REM': prodApk};
    final remApk = await apk.insert('remitos', {
      'numero': firestoreRemito['numero'],
      'fecha': firestoreRemito['fecha'],
      'total': firestoreRemito['total'],
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 50,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    for (final raw in firestoreRemito['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      final resolved = resolveRemoteLineProductoId(
        peerProductoId: (item['productoId'] as num?)?.toInt(),
        codigo: item['productoCodigo']?.toString(),
        localIdByCodigo: localByCodigo,
      );
      expect(resolved, prodApk);
      expect(resolved, isNot(item['productoId']));
      await apk.insert('remito_items', {
        'remitoId': remApk,
        'productoId': resolved,
        'cantidad': item['cantidad'],
        'precio': item['precio'],
        'subtotal': item['subtotal'],
        'costoUnitario': 20,
        'ganancia': 30,
      });
    }

    expect(await count(apk, 'remitos'), remitosWin);
    expect(await count(apk, 'remito_items'), itemsWin);
    expect(remitosWin, 1);
    expect(itemsWin, 1);
  });

  test('4) venta + compra convergen igual que remito (resolve por codigo)',
      () async {
    final win = await openNode(tmpWin);
    final prodWin = await win.insert('productos', {
      'codigo': 'SKU-VC',
      'descripcion': 'vc',
      'stock': 0,
      'precio': 10,
      'costo': 5,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final cliWin = await win.insert('clientes', {
      'nombre': 'Cli VC',
      'syncId': 'cli-vc-1',
      'activo': 1,
    });
    final provWin = await win.insert('proveedores', {
      'nombre': 'Prov VC',
      'syncId': 'prov-vc-1',
      'activo': 1,
    });
    final ventaWin = await win.insert('ventas', {
      'tipo': 'factura_b',
      'numero': 'V-ACEPT-4',
      'clienteId': cliWin,
      'fecha': DateTime.now().toIso8601String(),
      'total': 10,
      'descuento': 0,
      'iva': 0,
      'estado': 'confirmada',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 10,
      'estadoAfip': 'no_aplica',
      'cae': '',
      'puntoVenta': 0,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    await win.insert('ventas_items', {
      'ventaId': ventaWin,
      'productoId': prodWin,
      'productoDescripcion': 'vc',
      'cantidad': 1,
      'precio': 10,
      'subtotal': 10,
      'costoUnitario': 5,
      'ganancia': 5,
    });
    final compraWin = await win.insert('compras', {
      'proveedorId': provWin,
      'proveedorNombre': 'Prov VC',
      'numero': 'C-ACEPT-4',
      'fecha': DateTime.now().toIso8601String(),
      'total': 5,
      'descuento': 0,
      'iva': 0,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
      'estado': 'confirmada',
    });
    await win.insert('compra_items', {
      'compraId': compraWin,
      'productoId': prodWin,
      'productoDescripcion': 'vc',
      'cantidad': 1,
      'costo': 5,
      'subtotal': 5,
    });
    final ventasWin = await count(win, 'ventas');
    final ventasItemsWin = await count(win, 'ventas_items');
    final comprasWin = await count(win, 'compras');
    final compraItemsWin = await count(win, 'compra_items');

    final fsVenta = {
      'numero': 'V-ACEPT-4',
      'items': [
        {
          'productoId': 99901,
          'productoCodigo': 'SKU-VC',
          'cantidad': 1,
          'precio': 10,
          'subtotal': 10,
        },
      ],
    };
    final fsCompra = {
      'numero': 'C-ACEPT-4',
      'items': [
        {
          'productoId': 99902,
          'productoCodigo': 'SKU-VC',
          'cantidad': 1,
          'costo': 5,
          'subtotal': 5,
        },
      ],
    };

    final apk = await openNode(tmpApk);
    await seedAutoincrementOffset(apk, 3);
    final prodApk = await applyProductoFromRemote(apk, {
      'codigo': 'SKU-VC',
      'descripcion': 'vc',
      'stock': 0,
      'precio': 10,
      'costo': 5,
    });
    await apk.insert('clientes', {
      'nombre': 'Cli VC',
      'syncId': 'cli-vc-1',
      'activo': 1,
    });
    final provApk = await apk.insert('proveedores', {
      'nombre': 'Prov VC',
      'syncId': 'prov-vc-1',
      'activo': 1,
    });
    final byCodigo = {'SKU-VC': prodApk};

    final ventaApk = await apk.insert('ventas', {
      'tipo': 'factura_b',
      'numero': fsVenta['numero'],
      'fecha': DateTime.now().toIso8601String(),
      'total': 10,
      'descuento': 0,
      'iva': 0,
      'estado': 'confirmada',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 10,
      'estadoAfip': 'no_aplica',
      'cae': '',
      'puntoVenta': 0,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    for (final raw in fsVenta['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = resolveRemoteLineProductoId(
        peerProductoId: (item['productoId'] as num?)?.toInt(),
        codigo: item['productoCodigo']?.toString(),
        localIdByCodigo: byCodigo,
      );
      expect(pid, prodApk);
      await apk.insert('ventas_items', {
        'ventaId': ventaApk,
        'productoId': pid,
        'productoDescripcion': 'vc',
        'cantidad': item['cantidad'],
        'precio': item['precio'],
        'subtotal': item['subtotal'],
        'costoUnitario': 5,
        'ganancia': 5,
      });
    }

    final compraApk = await apk.insert('compras', {
      'proveedorId': provApk,
      'proveedorNombre': 'Prov VC',
      'numero': fsCompra['numero'],
      'fecha': DateTime.now().toIso8601String(),
      'total': 5,
      'descuento': 0,
      'iva': 0,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
      'estado': 'confirmada',
    });
    for (final raw in fsCompra['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = resolveRemoteLineProductoId(
        peerProductoId: (item['productoId'] as num?)?.toInt(),
        codigo: item['productoCodigo']?.toString(),
        localIdByCodigo: byCodigo,
      );
      expect(pid, prodApk);
      await apk.insert('compra_items', {
        'compraId': compraApk,
        'productoId': pid,
        'productoDescripcion': 'vc',
        'cantidad': item['cantidad'],
        'costo': item['costo'],
        'subtotal': item['subtotal'],
      });
    }

    expect(await count(apk, 'ventas'), ventasWin);
    expect(await count(apk, 'ventas_items'), ventasItemsWin);
    expect(await count(apk, 'compras'), comprasWin);
    expect(await count(apk, 'compra_items'), compraItemsWin);
  });

  test('5) cliente + proveedor sync por syncId', () async {
    final win = await openNode(tmpWin);
    await win.insert('clientes', {
      'nombre': 'Cliente Sync',
      'cuit': '20333333333',
      'syncId': 'cli-sync-acept',
      'activo': 1,
      'telefono': '111',
    });
    await win.insert('proveedores', {
      'nombre': 'Proveedor Sync',
      'syncId': 'prov-sync-acept',
      'activo': 1,
      'cuit': '30777777777',
    });
    final clientesWin = await count(win, 'clientes');
    final proveedoresWin = await count(win, 'proveedores');

    final fsCliente = {
      'syncId': 'cli-sync-acept',
      'nombre': 'Cliente Sync',
      'cuit': '20333333333',
      'telefono': '111',
    };
    final fsProveedor = {
      'syncId': 'prov-sync-acept',
      'nombre': 'Proveedor Sync',
      'cuit': '30777777777',
    };

    final apk = await openNode(tmpApk);

    Future<void> upsertCliente(Map<String, dynamic> remote) async {
      final syncId = remote['syncId'] as String;
      final found = await apk.query(
        'clientes',
        where: 'syncId = ?',
        whereArgs: [syncId],
        limit: 1,
      );
      final data = {
        'syncId': syncId,
        'nombre': remote['nombre'],
        'cuit': remote['cuit'] ?? '',
        'telefono': remote['telefono'] ?? '',
        'activo': 1,
      };
      if (found.isEmpty) {
        await apk.insert('clientes', data);
      } else {
        await apk.update(
          'clientes',
          data,
          where: 'id = ?',
          whereArgs: [found.first['id']],
        );
      }
    }

    Future<void> upsertProveedor(Map<String, dynamic> remote) async {
      final syncId = remote['syncId'] as String;
      final found = await apk.query(
        'proveedores',
        where: 'syncId = ?',
        whereArgs: [syncId],
        limit: 1,
      );
      final data = {
        'syncId': syncId,
        'nombre': remote['nombre'],
        'cuit': remote['cuit'] ?? '',
        'activo': 1,
      };
      if (found.isEmpty) {
        await apk.insert('proveedores', data);
      } else {
        await apk.update(
          'proveedores',
          data,
          where: 'id = ?',
          whereArgs: [found.first['id']],
        );
      }
    }

    await upsertCliente(fsCliente);
    await upsertProveedor(fsProveedor);
    await upsertCliente({...fsCliente, 'telefono': '222'});
    await upsertProveedor(fsProveedor);

    final clientes = await apk.query(
      'clientes',
      where: 'syncId = ?',
      whereArgs: ['cli-sync-acept'],
    );
    expect(clientes, hasLength(1));
    expect(clientes.first['telefono'], '222');

    final proveedores = await apk.query(
      'proveedores',
      where: 'syncId = ?',
      whereArgs: ['prov-sync-acept'],
    );
    expect(proveedores, hasLength(1));
    expect(proveedores.first['nombre'], 'Proveedor Sync');

    expect(await count(apk, 'clientes'), clientesWin);
    expect(await count(apk, 'proveedores'), proveedoresWin);
  });

  test(
      '6) stock ops: Win delta -2; APK parte en 0; apply remoto → mismo stock final',
      () async {
    const codigo = 'SKU-OPS-6';
    const opId = 'stock_op:acept-6-delta-2';
    const delta = -2;

    final win = await openNode(tmpWin);
    final prodWin = await win.insert('productos', {
      'codigo': codigo,
      'descripcion': 'ops',
      'stock': 0,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });

    final appliedWin = await win.transaction((txn) async {
      return InventoryLedgerService.instance.applyInTxn(
        txn,
        DomainEvent(
          eventId: opId,
          type: DomainEventType.ajusteInventario,
          aggregateType: 'ajuste',
          aggregateId: 'acept-6',
          createdBy: 'win',
          payload: {
            'documentType': 'ajuste',
            'documentId': 'acept-6',
            'motivo': 'venta',
            'lines': [
              InventoryLine(productoId: prodWin, cantidad: 2).toJson(),
            ],
          },
        ),
        sign: -1,
        movimientoTipo: 'salida',
        enqueueOutboundStockOps: false,
        // Simula política "permitir negativo" / origen ya comprometido.
        enforceStockPolicy: false,
      );
    });
    expect(appliedWin, isTrue);
    final stockWin = await stockOf(win, prodWin);
    expect(stockWin, -2);

    final fsOp = {
      'opId': opId,
      'codigo': codigo,
      'delta': delta,
      'documentType': 'ajuste',
      'documentId': 'acept-6',
      'status': 'applied',
    };

    final apk = await openNode(tmpApk);
    await seedAutoincrementOffset(apk, 4);
    final prodApk = await apk.insert('productos', {
      'codigo': codigo,
      'descripcion': 'ops',
      'stock': 0,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    expect(await stockOf(apk, prodApk), 0);
    expect(prodApk, isNot(prodWin));

    final appliedApk =
        await InventoryLedgerService.instance.applyRemoteStockOp(
      opId: fsOp['opId'] as String,
      productoId: prodApk,
      codigo: fsOp['codigo'] as String,
      delta: fsOp['delta'] as int,
      documentType: fsOp['documentType'] as String?,
      documentId: fsOp['documentId'] as String?,
      notify: false,
    );
    expect(appliedApk, isTrue);
    final stockApk = await stockOf(apk, prodApk);
    expect(stockApk, -2);
    expect(stockApk, stockWin);
  });

  test('7) watermark: pending_apply NO avanza (shouldAdvanceStockOpsWatermark)',
      () {
    expect(
      shouldAdvanceStockOpsWatermark(
        consideredValid: 0,
        skippedMissingProduct: 0,
        skippedPendingApply: 1,
        blockersParkedInHolds: true,
      ),
      isFalse,
      reason: 'pending_apply jamás debe adelantar watermark',
    );
    expect(
      shouldAdvanceStockOpsWatermark(
        consideredValid: 2,
        skippedMissingProduct: 0,
        skippedPendingApply: 3,
        truncatedByMaxApply: false,
      ),
      isFalse,
    );
    expect(
      shouldAdvanceStockOpsWatermark(
        consideredValid: 2,
        skippedMissingProduct: 0,
        skippedPendingApply: 0,
      ),
      isTrue,
    );
  });

  test('8) hold forceDueForCodigo tras llegada de producto', () async {
    final apk = await openNode(tmpApk);
    await StockOpsPullHoldStore.instance.upsert(
      opId: 'op-hold-sku-x',
      reason: StockOpsPullHoldStore.reasonMissingProduct,
      codigo: 'SKU-HOLD-8',
      delta: -1,
      at: DateTime.now().toUtc().toIso8601String(),
    );
    await StockOpsPullHoldStore.instance.upsert(
      opId: 'op-hold-sku-x',
      reason: StockOpsPullHoldStore.reasonMissingProduct,
      codigo: 'SKU-HOLD-8',
      delta: -1,
    );

    var due = await StockOpsPullHoldStore.instance.listDue(limit: 20);
    expect(
      due.where((e) => e['op_id'] == 'op-hold-sku-x'),
      isEmpty,
      reason: 'con backoff no debe estar due',
    );

    await applyProductoFromRemote(apk, {
      'codigo': 'SKU-HOLD-8',
      'descripcion': 'llegó',
      'stock': 0,
      'precio': 1,
      'costo': 0,
    });
    final n =
        await StockOpsPullHoldStore.instance.forceDueForCodigo('SKU-HOLD-8');
    expect(n, greaterThan(0));
    due = await StockOpsPullHoldStore.instance.listDue(limit: 20);
    expect(due.any((e) => e['op_id'] == 'op-hold-sku-x'), isTrue);
  });

  test('9) delete remito en Win → APK remueve por numero', () async {
    final win = await openNode(tmpWin);
    await win.insert('remitos', {
      'numero': 'R-DEL-9',
      'fecha': DateTime.now().toIso8601String(),
      'total': 10,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 10,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    await win.delete('remitos', where: 'numero = ?', whereArgs: ['R-DEL-9']);
    final remitosWin = await count(win, 'remitos');
    expect(remitosWin, 0);

    final fsDelete = {
      'numero': 'R-DEL-9',
      'tombstone': true,
      'deletedAt': DateTime.utc(2026, 7, 28).toIso8601String(),
      'opId': 'delete:remito:R-DEL-9',
    };

    final apk = await openNode(tmpApk);
    await apk.insert('remitos', {
      'numero': 'R-DEL-9',
      'fecha': DateTime.now().toIso8601String(),
      'total': 10,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 10,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    expect(await count(apk, 'remitos'), 1);

    if (fsDelete['tombstone'] == true) {
      await apk.delete(
        'remitos',
        where: 'numero = ?',
        whereArgs: [fsDelete['numero']],
      );
    }
    expect(await count(apk, 'remitos'), remitosWin);
  });

  test('10) cola offline: write local → upload map → apply en peer', () async {
    final win = await openNode(tmpWin);
    final prodWin = await win.insert('productos', {
      'codigo': 'SKU-OFF-10',
      'descripcion': 'offline',
      'stock': 0,
      'precio': 25,
      'costo': 10,
      'actualizadoEn': '2026-07-28T05:00:00.000Z',
    });
    final remWin = await win.insert('remitos', {
      'numero': 'R-OFF-10',
      'fecha': '2026-07-28T05:00:00.000',
      'total': 25,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 25,
      'observaciones': 'cola offline',
      'fechaCreacion': '2026-07-28T05:00:00.000',
    });
    await win.insert('remito_items', {
      'remitoId': remWin,
      'productoId': prodWin,
      'cantidad': 1,
      'precio': 25,
      'subtotal': 25,
      'costoUnitario': 10,
      'ganancia': 15,
    });
    final productosWin = await count(win, 'productos');
    final remitosWin = await count(win, 'remitos');
    final itemsWin = await count(win, 'remito_items');

    final uploadProducto = productToUploadMap(
      await productoByCodigo(win, 'SKU-OFF-10'),
    );
    final uploadRemito = {
      'numero': 'R-OFF-10',
      'fecha': '2026-07-28T05:00:00.000',
      'total': 25,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 25,
      'observaciones': 'cola offline',
      'items': [
        {
          'productoId': prodWin,
          'productoCodigo': 'SKU-OFF-10',
          'cantidad': 1,
          'precio': 25,
          'subtotal': 25,
        },
      ],
    };

    final apk = await openNode(tmpApk);
    await seedAutoincrementOffset(apk, 6);
    final prodApk = await applyProductoFromRemote(apk, uploadProducto);
    final byCodigo = {'SKU-OFF-10': prodApk};
    final remApk = await apk.insert('remitos', {
      'numero': uploadRemito['numero'],
      'fecha': uploadRemito['fecha'],
      'total': uploadRemito['total'],
      'descuento': uploadRemito['descuento'],
      'estado': uploadRemito['estado'],
      'estadoPago': uploadRemito['estadoPago'],
      'totalPagado': uploadRemito['totalPagado'],
      'saldoPendiente': uploadRemito['saldoPendiente'],
      'observaciones': uploadRemito['observaciones'],
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    for (final raw in uploadRemito['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = resolveRemoteLineProductoId(
        peerProductoId: (item['productoId'] as num?)?.toInt(),
        codigo: item['productoCodigo']?.toString(),
        localIdByCodigo: byCodigo,
      );
      expect(pid, isNotNull);
      await apk.insert('remito_items', {
        'remitoId': remApk,
        'productoId': pid,
        'cantidad': item['cantidad'],
        'precio': item['precio'],
        'subtotal': item['subtotal'],
        'costoUnitario': 10,
        'ganancia': 15,
      });
    }

    // Pads no cuentan como catálogo activo comparable; comparar entidad sync.
    expect(await count(apk, 'remitos'), remitosWin);
    expect(await count(apk, 'remito_items'), itemsWin);
    expect(productosWin, 1);
    final apkProd = await productoByCodigo(apk, 'SKU-OFF-10');
    expect(apkProd['descripcion'], 'offline');
    expect(apkProd['id'], isNot(prodWin));
  });
}
