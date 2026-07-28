import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/remote_line_product_resolve.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Convergencia mínima Windows↔Android por entidad (apply local simulado).
///
/// No usa Firestore real: demuestra que con resolve-by-codigo + FK ON,
/// headers e ítems convergen cuando el catálogo local tiene los códigos.
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
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrar();
  });

  Future<Database> openNode(Directory dir) async {
    await DatabaseHelper.instance.cerrar();
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(dir.path, 't.db'),
    );
    return DatabaseHelper.instance.database;
  }

  test('módulos: productos/remitos/ventas/compras/clientes/proveedores',
      () async {
    tmpWin = await Directory.systemTemp.createTemp('win_');
    tmpApk = await Directory.systemTemp.createTemp('apk_');

    // --- Windows seed ---
    final win = await openNode(tmpWin);
    final prodWin = await win.insert('productos', {
      'codigo': 'P-ZERO',
      'descripcion': 'sin stock',
      'stock': 0,
      'precio': 10,
      'costo': 1,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final cliWin = await win.insert('clientes', {
      'nombre': 'Cliente A',
      'cuit': '20111111111',
      'syncId': 'cli-sync-1',
      'activo': 1,
    });
    final provWin = await win.insert('proveedores', {
      'nombre': 'Prov A',
      'syncId': 'prov-sync-1',
      'activo': 1,
    });
    final remWin = await win.insert('remitos', {
      'numero': 'R-CONV-1',
      'clienteId': cliWin,
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
    await win.insert('remito_items', {
      'remitoId': remWin,
      'productoId': prodWin,
      'cantidad': 1,
      'precio': 10,
      'subtotal': 10,
      'costoUnitario': 1,
      'ganancia': 9,
    });
    final ventaWin = await win.insert('ventas', {
      'tipo': 'factura_b',
      'numero': 'V-CONV-1',
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
      'productoDescripcion': 'sin stock',
      'cantidad': 1,
      'precio': 10,
      'subtotal': 10,
      'costoUnitario': 1,
      'ganancia': 9,
    });
    final compraWin = await win.insert('compras', {
      'proveedorId': provWin,
      'proveedorNombre': 'Prov A',
      'numero': 'C-CONV-1',
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
      'productoDescripcion': 'sin stock',
      'cantidad': 1,
      'costo': 5,
      'subtotal': 5,
    });

    final winCounts = {
      'productos': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM productos')),
      'productosSinStock': Sqflite.firstIntValue(await win.rawQuery(
          'SELECT COUNT(*) FROM productos WHERE stock = 0')),
      'remitos': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM remitos')),
      'ventas': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM ventas')),
      'compras': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM compras')),
      'clientes': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM clientes')),
      'proveedores': Sqflite.firstIntValue(
          await win.rawQuery('SELECT COUNT(*) FROM proveedores')),
    };

    // Payload "Firestore" (lo que Windows sube — incluye productoCodigo + peer id).
    final firestoreRemito = {
      'numero': 'R-CONV-1',
      'items': [
        {
          'productoId': 9999, // peer Windows id distinto al local APK
          'productoCodigo': 'P-ZERO',
          'cantidad': 1,
          'precio': 10,
          'subtotal': 10,
        }
      ],
    };
    final firestoreProducto = {
      'codigo': 'P-ZERO',
      'descripcion': 'sin stock',
      'stock': 0,
    };
    final firestoreCliente = {
      'nombre': 'Cliente A',
      'cuit': '20111111111',
      'syncId': 'cli-sync-1',
    };
    final firestoreProveedor = {
      'nombre': 'Prov A',
      'syncId': 'prov-sync-1',
    };

    // --- Android apply (catálogo primero, luego docs) ---
    final apk = await openNode(tmpApk);
    final prodApk = await apk.insert('productos', {
      'codigo': firestoreProducto['codigo'],
      'descripcion': firestoreProducto['descripcion'],
      'stock': 0, // sync metadata fuerza 0; stock real vía stock_ops
      'precio': 10,
      'costo': 1,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    await apk.insert('clientes', {
      'nombre': firestoreCliente['nombre'],
      'cuit': firestoreCliente['cuit'],
      'syncId': firestoreCliente['syncId'],
      'activo': 1,
    });
    final provApk = await apk.insert('proveedores', {
      'nombre': firestoreProveedor['nombre'],
      'syncId': firestoreProveedor['syncId'],
      'activo': 1,
    });

    final localByCodigo = {'P-ZERO': prodApk};
    final remId = await apk.insert('remitos', {
      'numero': firestoreRemito['numero'],
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
    for (final raw in (firestoreRemito['items'] as List)) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = resolveRemoteLineProductoId(
        peerProductoId: (item['productoId'] as num?)?.toInt(),
        codigo: item['productoCodigo']?.toString(),
        localIdByCodigo: localByCodigo,
      );
      expect(pid, prodApk, reason: 'peer Windows id distinto; codigo resuelve');
      expect(item['productoId'], 9999);
      expect(pid, isNot(9999));
      await apk.insert('remito_items', {
        'remitoId': remId,
        'productoId': pid,
        'cantidad': item['cantidad'],
        'precio': item['precio'],
        'subtotal': item['subtotal'],
        'costoUnitario': 1,
        'ganancia': 9,
      });
    }

    final ventaApk = await apk.insert('ventas', {
      'tipo': 'factura_b',
      'numero': 'V-CONV-1',
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
    await apk.insert('ventas_items', {
      'ventaId': ventaApk,
      'productoId': prodApk,
      'productoDescripcion': 'sin stock',
      'cantidad': 1,
      'precio': 10,
      'subtotal': 10,
      'costoUnitario': 1,
      'ganancia': 9,
    });
    final compraApk = await apk.insert('compras', {
      'proveedorId': provApk,
      'proveedorNombre': 'Prov A',
      'numero': 'C-CONV-1',
      'fecha': DateTime.now().toIso8601String(),
      'total': 5,
      'descuento': 0,
      'iva': 0,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
      'estado': 'confirmada',
    });
    await apk.insert('compra_items', {
      'compraId': compraApk,
      'productoId': prodApk,
      'productoDescripcion': 'sin stock',
      'cantidad': 1,
      'costo': 5,
      'subtotal': 5,
    });

    final apkCounts = {
      'productos': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM productos')),
      'productosSinStock': Sqflite.firstIntValue(await apk.rawQuery(
          'SELECT COUNT(*) FROM productos WHERE stock = 0')),
      'remitos': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM remitos')),
      'ventas': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM ventas')),
      'compras': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM compras')),
      'clientes': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM clientes')),
      'proveedores': Sqflite.firstIntValue(
          await apk.rawQuery('SELECT COUNT(*) FROM proveedores')),
    };

    expect(apkCounts, winCounts,
        reason: 'misma cantidad de registros por módulo Win↔APK');

    try {
      await tmpWin.delete(recursive: true);
      await tmpApk.delete(recursive: true);
    } catch (_) {}
  });
}
