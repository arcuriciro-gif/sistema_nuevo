import 'dart:convert';
import 'dart:io';

import 'cert_lab_models.dart';
import 'cert_lab_productos.dart';
import 'cert_lab_registry.dart';
import 'cert_lab_remitos_clientes.dart';
import 'cert_lab_runner.dart';
import 'cert_lab_stock.dart';
import 'cert_lab_world.dart';

/// Corre un módulo N veces consecutivas. Un rojo → revoca certificación.
class CertLabConsecutiveRunner {
  CertLabConsecutiveRunner({
    required this.registry,
    this.outputDir,
  });

  final CertLabRegistry registry;
  final String? outputDir;

  Future<Map<String, dynamic>> runModule(
    CertLabModule module, {
    int? times,
  }) async {
    final n = times ?? registry.requiredConsecutive;
    final scenarios = switch (module) {
      CertLabModule.productos => [
          ...CertLabBattery.p0().where((s) => !s.id.startsWith('P0-99')),
          ...CertLabProductosScenarios.all(),
        ],
      CertLabModule.stock => [
          ...CertLabBattery.p0().where((s) => !s.id.startsWith('P0-99')),
          ...CertLabStockScenarios.all(),
        ],
      CertLabModule.remitos => CertLabRemitosScenarios.all(),
      CertLabModule.clientes => CertLabClientesScenarios.all(),
      _ => throw StateError(
          'Módulo ${module.title} aún no tiene batería. '
          'Orden: Productos → Stock → …',
        ),
    };

    final runs = <Map<String, dynamic>>[];
    for (var i = 1; i <= n; i++) {
      final report = await CertLabRunner(outputDir: outputDir).run(
        scenarios: scenarios,
        failFast: true,
      );
      final ok = report.ok;
      registry.recordRun(
        module,
        ok: ok,
        failure: ok
            ? null
            : report.results
                .where((r) => !r.ok)
                .map((r) => r.failure?.toHuman() ?? r.scenarioId)
                .join('\n'),
      );
      runs.add({
        'run': i,
        'ok': ok,
        'passed': report.passed,
        'failed': report.failed,
        'consecutive': registry.consecutiveGreen[module],
        'status': registry.status[module]?.name,
      });
      if (!ok) {
        break;
      }
    }

    final out = {
      'module': module.name,
      'title': module.title,
      'requiredConsecutive': registry.requiredConsecutive,
      'runs': runs,
      'registry': registry.toJson(),
      'verdict': registry.status[module] == CertLabModuleStatus.certified
          ? 'MODULO_CERTIFICADO'
          : 'MODULO_NO_CERTIFICADO',
    };

    await _write(out, module);
    return out;
  }

  Future<void> _write(Map<String, dynamic> out, CertLabModule module) async {
    final dirPath = outputDir ?? '/opt/cursor/artifacts/cert-lab';
    try {
      final dir = Directory(dirPath);
      await dir.create(recursive: true);
      final encoded = const JsonEncoder.withIndent('  ').convert(out);
      await File('$dirPath/module_${module.name}_latest.json')
          .writeAsString(encoded);
      final md = StringBuffer()
        ..writeln('# Cert Lab — ${module.title}')
        ..writeln()
        ..writeln('- verdict: ${out['verdict']}')
        ..writeln('- requiredConsecutive: ${out['requiredConsecutive']}')
        ..writeln();
      for (final r in (out['runs'] as List)) {
        final m = r as Map;
        md.writeln(
          '- run ${m['run']}: ${m['ok'] == true ? 'PASS' : 'FAIL'} '
          '(consec=${m['consecutive']} status=${m['status']})',
        );
      }
      await File('$dirPath/module_${module.name}_latest.md')
          .writeAsString(md.toString());
    } catch (_) {}
  }
}
