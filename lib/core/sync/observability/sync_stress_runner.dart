import 'dart:async';
import 'dart:math';

import '../sync_outbox.dart';
import 'sync_flight_recorder.dart';
import 'sync_observability_hub.dart';

/// Genera carga aleatoria durante [duration] (laboratorio / piloto controlado).
class SyncStressRunner {
  SyncStressRunner._();
  static final SyncStressRunner instance = SyncStressRunner._();

  bool _running = false;
  bool get isRunning => _running;
  int opsGenerated = 0;

  Future<Map<String, dynamic>> run({
    Duration duration = const Duration(seconds: 30),
    Duration tick = const Duration(milliseconds: 50),
  }) async {
    if (_running) {
      return {'error': 'already_running'};
    }
    _running = true;
    opsGenerated = 0;
    final rnd = Random(7);
    final started = DateTime.now().toUtc();
    final types = ['venta', 'compra', 'remito', 'cliente', 'producto', 'stock_op'];
    final sw = Stopwatch()..start();
    try {
      while (sw.elapsed < duration && _running) {
        final t = types[rnd.nextInt(types.length)];
        final id = 700000 + rnd.nextInt(50000);
        if (t == 'stock_op') {
          final opId = 'stress-stock-$opsGenerated';
          SyncObservabilityHub.instance.onEnqueue(
            opId: 'stock_op:$opId',
            entityType: 'stock_op',
            remoteId: opId,
          );
          await SyncOutbox.instance.enqueueStockOp(
            opId: opId,
            codigo: 'S${id % 1000}',
            delta: rnd.nextBool() ? 1 : -1,
          );
        } else {
          final opId = 'upsert:$t:$id';
          SyncObservabilityHub.instance.onEnqueue(
            opId: opId,
            entityType: t,
            localId: id,
          );
          await SyncOutbox.instance.enqueueUpsert(
            entityType: t,
            localId: id,
            forceBackground: t == 'producto',
          );
        }
        opsGenerated++;
        // Drenar un poco para no llenar infinito en demos cortas.
        if (opsGenerated % 20 == 0) {
          final batch = await SyncOutbox.instance.claimBatch(
            limit: 10,
            orderByPriority: true,
          );
          for (final op in batch) {
            final oid = op['op_id']?.toString() ?? '';
            SyncObservabilityHub.instance.onClaimed(oid);
            SyncObservabilityHub.instance.onSendStart(oid);
            await SyncOutbox.instance.ack(oid);
            SyncObservabilityHub.instance
                .onSendDone(oid, latencyMs: rnd.nextInt(40) + 5, error: false);
          }
        }
        await Future<void>.delayed(tick);
      }
    } finally {
      _running = false;
    }
    SyncFlightRecorder.instance.record(
      kind: 'stress',
      message: 'finished',
      data: {'ops': opsGenerated, 'sec': sw.elapsed.inSeconds},
    );
    return {
      'startedAt': started.toIso8601String(),
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
      'durationMs': sw.elapsedMilliseconds,
      'opsGenerated': opsGenerated,
      'dashboard': await SyncObservabilityHub.instance.dashboardSnapshot(),
    };
  }

  void stop() => _running = false;
}
