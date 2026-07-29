import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Batería completa = protocolo + contratos de motor.
///
/// Hoy P0-99 debe ser ROJO (inbound Windows no certificado).
/// Eso es correcto: el lab existe y bloquea certificación falsa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Cert Lab full battery: protocolo verde + P0-99 rojo (gate)', () async {
    final out = await Directory.systemTemp.createTemp('certlab_full_');
    final report = await CertLabRunner(outputDir: out.path).run(
      failFast: false,
    );
    // ignore: avoid_print
    print(report.toMarkdown());

    final protocol = report.results.where((r) => !r.scenarioId.startsWith('P0-99'));
    final contracts = report.results.where((r) => r.scenarioId.startsWith('P0-99'));

    for (final r in protocol) {
      expect(r.ok, isTrue, reason: r.failure?.toHuman() ?? r.scenarioId);
    }
    expect(contracts, isNotEmpty);
    expect(
      contracts.every((r) => !r.ok),
      isTrue,
      reason: 'P0-99 debe fallar hasta certificar inbound Windows',
    );
    expect(report.ok, isFalse, reason: 'batería completa no puede ser GREEN aún');

    final f = contracts.first.failure!;
    expect(f.file, contains('cert_lab_engine_manifest.dart'));
    expect(f.clazz, 'CertLabEngineManifest');
    expect(f.method, isNotEmpty);
    expect(f.firestorePath, isNotNull);
  });
}
