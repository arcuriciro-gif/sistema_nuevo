import 'dart:convert';
import 'dart:io';

import 'cert_lab_models.dart';
import 'cert_lab_world.dart';

/// Ejecuta la batería del laboratorio y escribe informe.
class CertLabRunner {
  CertLabRunner({this.outputDir});

  final String? outputDir;

  /// Corre escenarios. Por defecto detiene en el primer rojo (fail-fast).
  Future<CertLabReport> run({
    List<CertLabScenario>? scenarios,
    bool failFast = true,
  }) async {
    final list = scenarios ?? CertLabBattery.p0();
    final results = <CertLabScenarioResult>[];
    final allEvents = <CertLabEvent>[];
    var batteryOk = true;
    String? commit;
    try {
      final r = await Process.run('git', ['rev-parse', 'HEAD']);
      if (r.exitCode == 0) commit = (r.stdout as String).trim();
    } catch (_) {}

    for (final scenario in list) {
      final sw = Stopwatch()..start();
      CertLabWorld? world;
      try {
        world = await CertLabWorld.create();
        await scenario.run(world);
        allEvents.addAll(world.events);

        // Contratos de motor pueden tirar _CertLabContractException.
        final fail = await world.assertConverged(scenario.id);
        if (fail != null) {
          batteryOk = false;
          results.add(
            CertLabScenarioResult(
              scenarioId: scenario.id,
              title: scenario.title,
              ok: false,
              durationMs: sw.elapsedMilliseconds,
              failure: fail,
            ),
          );
          if (failFast) break;
          continue;
        }

        results.add(
          CertLabScenarioResult(
            scenarioId: scenario.id,
            title: scenario.title,
            ok: true,
            durationMs: sw.elapsedMilliseconds,
          ),
        );
      } on CertLabContractException catch (e) {
        batteryOk = false;
        results.add(
          CertLabScenarioResult(
            scenarioId: scenario.id,
            title: scenario.title,
            ok: false,
            durationMs: sw.elapsedMilliseconds,
            failure: e.failure,
          ),
        );
        if (failFast) {
          await world?.dispose();
          break;
        }
      } catch (e, st) {
        batteryOk = false;
        results.add(
          CertLabScenarioResult(
            scenarioId: scenario.id,
            title: scenario.title,
            ok: false,
            durationMs: sw.elapsedMilliseconds,
            failure: CertLabFailure(
              scenarioId: scenario.id,
              entity: CertLabEntity.movimiento,
              where: 'scenario.run',
              message: e.toString(),
              stackTrace: st.toString(),
              file: 'lib/core/cert/lab/cert_lab_runner.dart',
              clazz: 'CertLabRunner',
              method: 'run',
            ),
          ),
        );
        if (failFast) {
          await world?.dispose();
          break;
        }
      } finally {
        await world?.dispose();
      }
    }

    final report = CertLabReport(
      at: DateTime.now().toUtc(),
      commit: commit,
      ok: batteryOk && results.isNotEmpty && results.every((r) => r.ok),
      results: results,
      events: allEvents,
    );

    await _write(report);
    return report;
  }

  /// Corre P0 protocolo (sin P0-99) — valida que el lab mismo funciona.
  Future<CertLabReport> runProtocolOnly({bool failFast = true}) {
    final protocol = CertLabBattery.p0()
        .where((s) => !s.id.startsWith('P0-99'))
        .toList();
    return run(scenarios: protocol, failFast: failFast);
  }

  Future<void> _write(CertLabReport report) async {
    final dirPath = outputDir ?? '/opt/cursor/artifacts/cert-lab';
    try {
      final dir = Directory(dirPath);
      await dir.create(recursive: true);
      final stamp = report.at.toIso8601String().replaceAll(':', '-');
      final jsonFile = File('$dirPath/cert_lab_$stamp.json');
      final mdFile = File('$dirPath/cert_lab_$stamp.md');
      final latestJson = File('$dirPath/cert_lab_latest.json');
      final latestMd = File('$dirPath/cert_lab_latest.md');
      final encoded = const JsonEncoder.withIndent('  ').convert(report.toJson());
      await jsonFile.writeAsString(encoded);
      await mdFile.writeAsString(report.toMarkdown());
      await latestJson.writeAsString(encoded);
      await latestMd.writeAsString(report.toMarkdown());
    } catch (_) {
      // En entornos sin /opt/cursor, silencioso: el test igual valida.
    }
  }
}
