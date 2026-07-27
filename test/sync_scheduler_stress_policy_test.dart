import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/import/import_checkpoint_store.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Simula cola de 100k ops de fondo + críticos intercalados.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('planTick con 100k fondo nunca deja críticos en 0', () {
    final plan = SyncSchedulerPolicy.planTick(
      pendingCritical: 3,
      pendingBackground: 100000,
      isWindows: false,
    );
    expect(plan.criticalClaim, 3);
    expect(plan.backgroundClaim, lessThanOrEqualTo(2));
  });

  test('checkpoint import 50k no reinicia desde 0', () async {
    final tmp = await Directory.systemTemp.createTemp('imp50k_');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 'test.db'),
    );
    final store = ImportCheckpointStore.instance;
    final job = await store.startJob(
      sourceName: 'catalogo_50k.xlsx',
      totalRows: 50000,
    );
    await store.saveProgress(
      ImportCheckpoint(
        jobId: job.jobId,
        sourceName: job.sourceName,
        totalRows: 50000,
        nextRowIndex: 27500,
        imported: 20000,
        updated: 7000,
        skipped: 500,
        status: 'running',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    final again = await store.loadRunning();
    expect(again!.nextRowIndex, 27500);
    expect(again.nextRowIndex, isNot(0));
  });
}
