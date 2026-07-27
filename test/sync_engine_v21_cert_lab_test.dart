import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/observability/sync_benchmark_runner.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_certification_runner.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_flight_recorder.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_observability_hub.dart';
import 'package:sistema_nuevo/core/sync/observability/sync_stress_runner.dart';
import 'package:sistema_nuevo/core/sync/scheduler/sync_scheduler.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Certificación lab Sync Engine 2.1 (observabilidad / SLA / breaker).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync21_cert_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 'test.db'),
    );
    SyncScheduler.instance.resetForTests();
    SyncObservabilityHub.instance.resetForTests();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('Flight recorder + hub enqueue wire', () async {
    final hub = SyncObservabilityHub.instance;
    hub.onEnqueue(opId: 'upsert:venta:1', entityType: 'venta', localId: 1);
    hub.onClaimed('upsert:venta:1');
    hub.onSendStart('upsert:venta:1');
    hub.onSendDone('upsert:venta:1', latencyMs: 12, error: false);
    expect(SyncFlightRecorder.instance.last().length, greaterThanOrEqualTo(2));
    expect(hub.traces.get('upsert:venta:1')?.success, isTrue);
  });

  test('Benchmark lab 100 ventas + PDF', () async {
    final report = await SyncBenchmarkRunner.instance.run(includeHeavy: false);
    final v100 = report.data['scenarios']['ventas_100'] as Map;
    expect(v100['n'], 100);
    expect(v100['p95_ms'], isA<int>());
    final outDir = Directory('/opt/cursor/artifacts/sync-engine-2.1-cert');
    await outDir.create(recursive: true);
    await report.writePdf('${outDir.path}/benchmark_report.pdf');
    await File('${outDir.path}/benchmark_lab.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.data),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Stress runner corto', () async {
    final r = await SyncStressRunner.instance.run(
      duration: const Duration(seconds: 3),
      tick: const Duration(milliseconds: 20),
    );
    expect(r['opsGenerated'], greaterThan(10));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('Certification runner genera informe', () async {
    final out = '/opt/cursor/artifacts/sync-engine-2.1-cert';
    final report = await SyncCertificationRunner.instance.runAndWrite(
      outputDir: out,
      heavyBenchmark: false,
      stressDuration: const Duration(seconds: 3),
    );
    expect(report['schemaVersion'], DatabaseHelper.schemaVersion);
    expect(File('$out/certification_report.json').existsSync(), isTrue);
    expect(File('$out/certification_report.md').existsSync(), isTrue);
    // En lab sin Firebase, el veredicto puede ser REQUIERE_CORRECCIONES
    // por firebaseReady=false; igual debe existir evidencia.
    expect(report['verdict'], isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
