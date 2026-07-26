import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncOutbox — desglose pendientes', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('outbox_bd_');
      await DatabaseHelper.instance.resetForTests(
        absolutePath: p.join(tmp.path, 'test.db'),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('formatBreakdown etiquetas en español', () {
      expect(
        SyncOutbox.formatBreakdown({
          'producto': 8,
          'remito': 3,
          'stock_op': 2,
        }),
        '8 productos, 3 remitos, 2 stock',
      );
    });

    test('pendingBreakdown agrupa por tipo', () async {
      await SyncOutbox.instance.enqueueUpsert(entityType: 'producto', localId: 1);
      await SyncOutbox.instance.enqueueUpsert(entityType: 'producto', localId: 2);
      await SyncOutbox.instance.enqueueUpsert(entityType: 'remito', localId: 9);

      final bd = await SyncOutbox.instance.pendingBreakdown();
      expect(bd['producto'], 2);
      expect(bd['remito'], 1);
    });

    test('ackOrphanUpserts limpia filas locales inexistentes', () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('productos', {
        'codigo': 'P-OK',
        'descripcion': 'existe',
        'marca': '',
        'categoria': '',
        'proveedor': '',
        'ubicacion': '',
        'stock': 0,
        'costo': 0,
        'precio': 0,
        'observaciones': '',
        'foto': '',
      });
      final okId = (await db.query('productos', limit: 1)).first['id'] as int;

      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'producto', localId: okId);
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'producto', localId: 999999);

      final cleaned = await SyncOutbox.instance.ackOrphanUpserts();
      expect(cleaned, 1);
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.pending),
        1,
      );
      expect(
        await SyncOutbox.instance.countByStatus(SyncOutboxStatus.acked),
        1,
      );
    });
  });
}
