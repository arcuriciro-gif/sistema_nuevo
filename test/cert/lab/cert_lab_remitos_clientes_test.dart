@Tags(['cert-lab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Remitos + Clientes — servicios reales, gate mínimo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Remitos REM-01 verde', () async {
    final out = await Directory.systemTemp.createTemp('cert_rem_');
    final report = await CertLabRunner(outputDir: out.path).run(
      scenarios: CertLabRemitosScenarios.all(),
      failFast: true,
    );
    // ignore: avoid_print
    print(report.toMarkdown());
    expect(report.ok, isTrue, reason: report.results
        .where((r) => !r.ok)
        .map((r) => r.failure?.toHuman() ?? r.scenarioId)
        .join('\n'));
  });

  test('Clientes CLI-01 verde', () async {
    final out = await Directory.systemTemp.createTemp('cert_cli_');
    final report = await CertLabRunner(outputDir: out.path).run(
      scenarios: CertLabClientesScenarios.all(),
      failFast: true,
    );
    // ignore: avoid_print
    print(report.toMarkdown());
    expect(report.ok, isTrue, reason: report.results
        .where((r) => !r.ok)
        .map((r) => r.failure?.toHuman() ?? r.scenarioId)
        .join('\n'));
  });

  test('Remitos + Clientes: 3 consecutivas cada uno', () async {
    final out = await Directory.systemTemp.createTemp('cert_rc3_');
    final registry = CertLabRegistry(requiredConsecutive: 3);
    final rem = await CertLabConsecutiveRunner(
      registry: registry,
      outputDir: out.path,
    ).runModule(CertLabModule.remitos, times: 3);
    expect(rem['verdict'], 'MODULO_CERTIFICADO');

    final registry2 = CertLabRegistry(requiredConsecutive: 3);
    final cli = await CertLabConsecutiveRunner(
      registry: registry2,
      outputDir: out.path,
    ).runModule(CertLabModule.clientes, times: 3);
    expect(cli['verdict'], 'MODULO_CERTIFICADO');
  });
}
