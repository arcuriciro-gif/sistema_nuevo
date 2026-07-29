import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Módulo Productos — código real (ProductoService) + oráculo.
///
/// CI corre 3 consecutivas. Certificación plena exige 20 (mission gate).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Productos: 1 corrida escenarios reales verdes', () async {
    final out = await Directory.systemTemp.createTemp('cert_prod_');
    final report = await CertLabRunner(outputDir: out.path).run(
      scenarios: CertLabProductosScenarios.all(),
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

  test('Productos: 3 consecutivas (gate CI)', () async {
    final out = await Directory.systemTemp.createTemp('cert_prod3_');
    final registry = CertLabRegistry(requiredConsecutive: 3);
    final result = await CertLabConsecutiveRunner(
      registry: registry,
      outputDir: out.path,
    ).runModule(CertLabModule.productos, times: 3);
    // ignore: avoid_print
    print(result);
    expect(result['verdict'], 'MODULO_CERTIFICADO');
    expect(registry.status[CertLabModule.productos], CertLabModuleStatus.certified);
  });
}
