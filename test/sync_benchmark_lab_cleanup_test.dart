import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/observability/sync_benchmark_runner.dart';
import 'package:sistema_nuevo/core/sync/sync_outbox.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Campo: Benchmark lab dejaba 500 productos pending → Panel AMARILLO.
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
    tmp = await Directory.systemTemp.createTemp('bench_lab_');
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

  test('ackLabBenchmarkGarbage limpia producto 800xxx y venta 900xxx', () async {
    final outbox = SyncOutbox.instance;
    for (var i = 1; i <= 12; i++) {
      await outbox.enqueueUpsert(
        entityType: 'producto',
        localId: SyncOutbox.labProductoLocalIdMin + i,
        forceBackground: true,
      );
    }
    await outbox.enqueueUpsert(
      entityType: 'venta',
      localId: SyncOutbox.labVentaLocalIdMin + 1,
    );
    // Negocio real: no debe tocarse.
    await outbox.enqueueUpsert(entityType: 'producto', localId: 42);

    final cleaned = await outbox.ackLabBenchmarkGarbage();
    expect(cleaned, greaterThanOrEqualTo(13));

    final bd = await outbox.pendingBreakdown();
    expect(bd['producto'] ?? 0, 1); // solo el 42
    expect(bd['venta'] ?? 0, 0);
  });

  test('Benchmark lab no deja cola L3 de 500 al terminar', () async {
    final report = await SyncBenchmarkRunner.instance.run(
      includeVentas1000: false,
    );
    final cleaned = (report.data['labCleanupAcked'] as num).toInt();
    expect(cleaned, greaterThanOrEqualTo(500));

    final pending = await SyncOutbox.instance.listPendingPreview(limit: 50);
    final labLeft = pending.where((r) {
      final id = (r['entity_local_id'] as num?)?.toInt() ?? 0;
      final type = r['entity_type']?.toString() ?? '';
      if (type == 'producto' &&
          id >= SyncOutbox.labProductoLocalIdMin &&
          id <= SyncOutbox.labProductoLocalIdMax) {
        return true;
      }
      if (type == 'venta' &&
          id >= SyncOutbox.labVentaLocalIdMin &&
          id <= SyncOutbox.labVentaLocalIdMax) {
        return true;
      }
      return false;
    }).length;
    expect(labLeft, 0);
  });
}
