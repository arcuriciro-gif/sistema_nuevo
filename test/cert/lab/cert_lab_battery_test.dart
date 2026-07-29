import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/lab/cert_lab.dart';

/// Batería completa = protocolo + contrato de motor (P0-99).
///
/// Tras hardCap≤4 + soft-pull stock_ops, P0-99 debe ser VERDE.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Cert Lab full battery: protocolo + P0-99 verdes', () async {
    final out = await Directory.systemTemp.createTemp('certlab_full_');
    final report = await CertLabRunner(outputDir: out.path).run(
      failFast: false,
    );
    // ignore: avoid_print
    print(report.toMarkdown());

    for (final r in report.results) {
      expect(
        r.ok,
        isTrue,
        reason: r.failure?.toHuman() ?? r.scenarioId,
      );
    }
    expect(report.ok, isTrue);
    expect(
      CertLabEngineManifest.windowsAutomaticStockInboundCertified,
      isTrue,
    );
    expect(CertLabEngineManifest.realFirebaseTripleHopCertified, isFalse);
  });
}
