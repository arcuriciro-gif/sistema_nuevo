import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/database/database_helper.dart';
import 'package:sistema_nuevo/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('listarDocumentosVenta une facturas y remitos por fecha', () async {
    final tmp = await Directory.systemTemp.createTemp('ventas_tot_');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 'test.db'),
    );
    final db = await DatabaseHelper.instance.database;

    final clienteId = await db.insert('clientes', {'nombre': 'Cliente X'});
    await db.insert('remitos', {
      'numero': 'R-00001',
      'clienteId': clienteId,
      'fecha': '2026-01-01T10:00:00.000',
      'fechaCreacion': '2026-01-01T10:00:00.000',
      'total': 100,
      'estado': 'confirmado',
    });
    await db.insert('ventas', {
      'numero': 'A-000001',
      'tipo': 'factura_a',
      'clienteId': clienteId,
      'fecha': '2026-01-02T12:00:00.000',
      'fechaCreacion': '2026-01-02T12:00:00.000',
      'total': 250,
      'estado': 'confirmada',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 250,
    });

    final n = await AnalyticsService.instance.cantidadDocumentosVenta();
    expect(n, 2);

    final docs = await AnalyticsService.instance.listarDocumentosVenta();
    expect(docs.length, 2);
    // Más reciente primero: factura del 2/1, luego remito del 1/1.
    expect(docs.first['numero'], 'A-000001');
    expect(docs.first['origen'], 'venta');
    expect(docs.last['numero'], 'R-00001');
    expect(docs.last['origen'], 'remito');
  });
}
