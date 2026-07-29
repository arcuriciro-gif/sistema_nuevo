@Tags(['cert-lab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Módulo Stock — RemitoService / ledger reales + oráculo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Stock: 1 corrida escenarios reales verdes', () async {
    final out = await Directory.systemTemp.createTemp('cert_stk_');
    final report = await CertLabRunner(outputDir: out.path).run(
      scenarios: CertLabStockScenarios.all(),
      failFast: true,
    );
    // ignore: avoid_print
    print(report.toMarkdown());
    expect(
      report.ok,
      isTrue,
      reason: report.results
          .where((r) => !r.ok)
          .map((r) => r.failure?.toHuman() ?? r.scenarioId)
          .join('\n'),
    );
  });

  test('Stock: 3 consecutivas (gate CI)', () async {
    final out = await Directory.systemTemp.createTemp('cert_stk3_');
    final registry = CertLabRegistry(requiredConsecutive: 3);
    final result = await CertLabConsecutiveRunner(
      registry: registry,
      outputDir: out.path,
    ).runModule(CertLabModule.stock, times: 3);
    // ignore: avoid_print
    print(result);
    expect(result['verdict'], 'MODULO_CERTIFICADO');
    expect(registry.status[CertLabModule.stock], CertLabModuleStatus.certified);
  });
}
