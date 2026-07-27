import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../database/database_helper.dart';
import '../scheduler/sync_scheduler.dart';
import 'sync_benchmark_runner.dart';
import 'sync_diagnostic_service.dart';
import 'sync_observability_hub.dart';
import 'sync_report_pdf.dart';
import 'sync_stress_runner.dart';

/// Genera informe de certificación automática (lab / piloto).
class SyncCertificationRunner {
  SyncCertificationRunner._();
  static final SyncCertificationRunner instance = SyncCertificationRunner._();

  Future<Map<String, dynamic>> runAndWrite({
    String outputDir = '/opt/cursor/artifacts/sync-engine-2.1-cert',
    bool heavyBenchmark = false,
    Duration stressDuration = const Duration(seconds: 15),
  }) async {
    final started = DateTime.now().toUtc();
    final dir = Directory(outputDir);
    await dir.create(recursive: true);

    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {}

    String? commit;
    try {
      final r = await Process.run('git', ['rev-parse', 'HEAD']);
      if (r.exitCode == 0) commit = (r.stdout as String).trim();
    } catch (_) {}

    final diag = await SyncDiagnosticService.instance.diagnose();
    final bench = await SyncBenchmarkRunner.instance.run(
      includeHeavy: heavyBenchmark,
      includeVentas1000: heavyBenchmark,
    );
    final stress =
        await SyncStressRunner.instance.run(duration: stressDuration);
    final dash = await SyncObservabilityHub.instance.dashboardSnapshot();
    final engine = SyncScheduler.instance.engineSnapshot();

    // Veredicto lab: no puede ser CERTIFICADO producción sin hop remoto.
    // diag.ok exige firebaseReady — en lab sin nube no bloquea observabilidad.
    final scenarios = (bench.data['scenarios'] as Map?) ?? const {};
    final observabilityOk = scenarios['ventas_100'] != null &&
        (stress['opsGenerated'] as int? ?? 0) > 0 &&
        SyncObservabilityHub.instance.flight.last(n: 5).isNotEmpty;
    final verdict = !observabilityOk
        ? 'REQUIERE_CORRECCIONES'
        : 'APTO_LAB_OBSERVABILIDAD — requiere smoke EXE↔APK para producción';

    final report = <String, dynamic>{
      'version': info?.version ?? '1.4.1',
      'buildNumber': info?.buildNumber ?? '68',
      'schemaVersion': DatabaseHelper.schemaVersion,
      'commit': commit,
      'startedAt': started.toIso8601String(),
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
      'environment': {
        'os': Platform.operatingSystem,
        'labOnly': true,
        'windowsExe': false,
        'androidApk': false,
        'firestoreReal': false,
      },
      'verdict': verdict,
      'diagnosticOk': diag.ok,
      'observabilityOk': observabilityOk,
      'diagnostic': diag.toJson(),
      'benchmark': bench.data,
      'stress': stress,
      'dashboard': dash,
      'engine': engine,
      'evidences': {
        'flightTail': SyncObservabilityHub.instance.flight.dumpJson(n: 50),
        'sla': dash['sla'],
        'circuit': dash['circuitBreaker'],
        'history': dash['history'],
        'rssBytes': dash['rssBytes'],
      },
    };

    final jsonFile = File('$outputDir/certification_report.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    final md = File('$outputDir/certification_report.md');
    await md.writeAsString(
      _toMarkdown(report, bench.toMarkdown(), diag.toHumanText()),
    );
    try {
      await SyncReportPdf.writeBenchmarkPdf(
        path: '$outputDir/benchmark_report.pdf',
        report: bench.data,
      );
      await SyncReportPdf.writeCertificationPdf(
        path: '$outputDir/certification_report.pdf',
        report: report,
      );
    } catch (_) {}
    return report;
  }

  String _toMarkdown(
    Map<String, dynamic> report,
    String benchMd,
    String diagText,
  ) {
    return '''
# Informe de certificación Sync Engine 2.1

- **Versión:** ${report['version']}+${report['buildNumber']}
- **Schema:** ${report['schemaVersion']}
- **Commit:** ${report['commit'] ?? 'n/a'}
- **Inicio:** ${report['startedAt']}
- **Fin:** ${report['finishedAt']}
- **Veredicto:** ${report['verdict']}

## Entorno
```json
${const JsonEncoder.withIndent('  ').convert(report['environment'])}
```

## Diagnóstico
```
$diagText
```

## Benchmark
$benchMd

## Stress
- ops: ${(report['stress'] as Map)['opsGenerated']}
- durationMs: ${(report['stress'] as Map)['durationMs']}

## Nota
Este informe **no** certifica hop Venta→Firestore→otro dispositivo.
Para CERTIFICADO PARA PRODUCCIÓN adjuntar latencias P50/P95 de campo.
''';
  }
}
