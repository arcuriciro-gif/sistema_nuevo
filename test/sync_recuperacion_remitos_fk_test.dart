import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/remote_line_product_resolve.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Demuestra la regresión FK: peer productoId + foreign_keys ON.
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
    tmp = await Directory.systemTemp.createTemp('sync_rec_');
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

  test('peer productoId inexistente + FK ON → insert ítem falla', () async {
    final db = await DatabaseHelper.instance.database;
    final rid = await db.insert('remitos', {
      'numero': 'R-REC-1',
      'fecha': DateTime.now().toIso8601String(),
      'total': 100,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 100,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });

    // Simula bug viejo: usar id del PC (99) que no existe en APK.
    expect(
      () async {
        await db.insert('remito_items', {
          'remitoId': rid,
          'productoId': 99,
          'cantidad': 1,
          'precio': 100,
          'subtotal': 100,
          'costoUnitario': 0,
          'ganancia': 0,
        });
      }(),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('resolver por codigo: remito se guarda aunque falte producto', () async {
    final db = await DatabaseHelper.instance.database;
    final rid = await db.insert('remitos', {
      'numero': 'R-REC-2',
      'fecha': DateTime.now().toIso8601String(),
      'total': 100,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 100,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });

    final localId = resolveRemoteLineProductoId(
      peerProductoId: 99,
      codigo: 'SKU-MISSING',
      localIdByCodigo: const {},
    );
    expect(localId, isNull);
    // Remito header queda; sin ítem (no FK crash).
    final rows = await db.query('remitos', where: 'id = ?', whereArgs: [rid]);
    expect(rows, hasLength(1));
  });

  test('con producto local por codigo: ítem inserta OK', () async {
    final db = await DatabaseHelper.instance.database;
    final pid = await db.insert('productos', {
      'codigo': 'SKU-OK',
      'descripcion': 'x',
      'stock': 0,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final rid = await db.insert('remitos', {
      'numero': 'R-REC-3',
      'fecha': DateTime.now().toIso8601String(),
      'total': 100,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 100,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
    final localId = resolveRemoteLineProductoId(
      peerProductoId: 9999,
      codigo: 'SKU-OK',
      localIdByCodigo: {'SKU-OK': pid},
    );
    expect(localId, pid);
    await db.insert('remito_items', {
      'remitoId': rid,
      'productoId': localId,
      'cantidad': 1,
      'precio': 100,
      'subtotal': 100,
      'costoUnitario': 0,
      'ganancia': 0,
    });
    final items = await db.query('remito_items', where: 'remitoId = ?', whereArgs: [rid]);
    expect(items, hasLength(1));
  });
}
