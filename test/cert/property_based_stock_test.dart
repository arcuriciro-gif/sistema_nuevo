import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/cert/stock_real_harness.dart';
import 'package:sistema_nuevo/core/cert/stock_reference_model.dart';
import 'package:sistema_nuevo/core/cert/stock_sequence_generator.dart';

/// Fase 4+5: property-based + modelo de referencia vs implementación real.
///
/// No valida casos específicos: valida propiedades sobre miles de secuencias.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const seedStock = {'A': 100, 'B': 100, 'C': 100};
  final model = StockReferenceModel();

  group('PBT — modelo de referencia (propiedades cloud+local)', () {
    test('2000 secuencias: proyección consistente + G1 (retries no duplican)', () {
      final rnd = Random(20260727);
      final gen = StockSequenceGenerator(rnd, productos: seedStock.keys.toList());
      var checked = 0;
      for (var i = 0; i < 2000; i++) {
        final seq = gen.generate(
          length: 40 + rnd.nextInt(40),
          includePoison: false,
        );
        var s = StockRefState.initial(seedStock);
        s = model.reduceAll(s, seq);
        expect(
          s.allProjectionsConsistent,
          isTrue,
          reason: 'seq#$i\n${encodeSequence(seq)}',
        );
        // Tras drain: si no hay dead, stock local == cloud
        if (s.outboxDead.isEmpty && s.outboxPending.isEmpty) {
          for (final cod in seedStock.keys) {
            expect(
              s.stock[cod],
              s.cloudStock[cod],
              reason: 'G6 fail seq#$i cod=$cod\n${encodeSequence(seq)}',
            );
          }
        }
        checked++;
      }
      expect(checked, 2000);
    });

    test('500 secuencias con poison: ledger consistente aunque cloud diverge', () {
      final rnd = Random(99);
      final gen = StockSequenceGenerator(rnd, productos: ['A', 'B']);
      for (var i = 0; i < 500; i++) {
        final seq = gen.generate(length: 30, includePoison: true);
        var s = StockRefState.initial({'A': 80, 'B': 80});
        s = model.reduceAll(s, seq);
        expect(
          s.allProjectionsConsistent,
          isTrue,
          reason: 'poison seq#$i\n${encodeSequence(seq)}',
        );
      }
    });
  });

  group('PBT — referencia vs SQLite real (solo local/remote)', () {
    // Windows CI: abrir/cerrar SQLite por secuencia es ~10× más lento.
    final localSeqs = Platform.isWindows ? 60 : 800;
    final peerSeqs = Platform.isWindows ? 40 : 400;

    test('800 secuencias locales: stock real == stock ref', () async {
      final rnd = Random(42);
      final gen = StockSequenceGenerator(rnd, productos: seedStock.keys.toList());
      var failures = <String>[];

      for (var i = 0; i < localSeqs; i++) {
        // Solo eventos locales + replays (sin remote del mismo device)
        final raw = gen.generate(length: 25, includeNetwork: false);
        final seq = raw
            .where((e) => e is LocalApply || e is LocalReplay || e is CrashAfterCommit)
            .toList();
        if (seq.whereType<LocalApply>().isEmpty) continue;

        final refInitial = StockRefState.initial(seedStock);
        final refFinal = reduceLocalOnly(model, refInitial, seq);

        final tmp = await Directory.systemTemp.createTemp('pbt_real_');
        final harness = StockRealHarness(tmpDir: tmp);
        try {
          SharedPreferences.setMockInitialValues({});
          await harness.open(seedStock);
          for (final e in seq) {
            await harness.applyLocalish(e);
          }
          final real = await harness.stocks();
          final okProj = await harness.allProjectionsOk();
          if (!okProj) {
            failures.add('proyección seq#$i\n${encodeSequence(seq)}');
          }
          for (final cod in seedStock.keys) {
            if (real[cod] != refFinal.stock[cod]) {
              failures.add(
                'stock mismatch seq#$i $cod real=${real[cod]} ref=${refFinal.stock[cod]}\n'
                '${encodeSequence(seq)}',
              );
            }
          }
          await harness.close();
        } finally {
          try {
            await tmp.delete(recursive: true);
          } catch (_) {}
        }

        if (failures.length >= 3) break; // fail fast con muestras
      }

      expect(failures, isEmpty, reason: failures.take(3).join('\n---\n'));
    }, timeout: Timeout(Duration(minutes: Platform.isWindows ? 4 : 8)));

    test('400 secuencias peer-only (RemoteApply): stock real == ref', () async {
      final rnd = Random(77);
      var compared = 0;
      final failures = <String>[];

      for (var i = 0; i < peerSeqs; i++) {
        final n = 5 + rnd.nextInt(15);
        final ops = <RemoteApply>[];
        for (var j = 0; j < n; j++) {
          final cod = seedStock.keys.elementAt(rnd.nextInt(3));
          var delta = rnd.nextInt(4) + 1;
          if (rnd.nextBool()) delta = -delta;
          ops.add(RemoteApply(
            opId: 'peer:$i:$j',
            codigo: cod,
            delta: delta,
          ));
        }
        // Duplicar algunos (retry)
        final withRetries = <StockCertEvent>[
          ...ops,
          ...ops.take(rnd.nextInt(ops.length) + 1),
        ];

        final ref = model.reduceAll(
          StockRefState.initial(seedStock),
          withRetries,
        );

        final tmp = await Directory.systemTemp.createTemp('pbt_peer_');
        final harness = StockRealHarness(tmpDir: tmp);
        try {
          SharedPreferences.setMockInitialValues({});
          await harness.open(seedStock);
          for (final e in withRetries) {
            await harness.applyLocalish(e);
          }
          final real = await harness.stocks();
          for (final cod in seedStock.keys) {
            if (real[cod] != ref.stock[cod]) {
              failures.add(
                'peer seq#$i $cod real=${real[cod]} ref=${ref.stock[cod]}\n'
                '${encodeSequence(withRetries)}',
              );
            }
          }
          await harness.close();
        } finally {
          try {
            await tmp.delete(recursive: true);
          } catch (_) {}
        }
        compared++;
        if (failures.length >= 3) break;
      }

      expect(compared, greaterThan(Platform.isWindows ? 20 : 100));
      expect(failures, isEmpty, reason: failures.take(3).join('\n---\n'));
    }, timeout: Timeout(Duration(minutes: Platform.isWindows ? 3 : 5)));
  });
}
