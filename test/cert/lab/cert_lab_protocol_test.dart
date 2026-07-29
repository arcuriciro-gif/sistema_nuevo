@Tags(['cert-lab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Batería protocolo P0 (sin contratos de motor).
/// Debe estar VERDE: demuestra que el laboratorio funciona.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Cert Lab protocolo P0: Win=Android=Firestore en escenarios de uso', () async {
    final out = await Directory.systemTemp.createTemp('certlab_out_');
    final report = await CertLabRunner(outputDir: out.path).runProtocolOnly(
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
    expect(report.passed, greaterThanOrEqualTo(10));
  });
}
