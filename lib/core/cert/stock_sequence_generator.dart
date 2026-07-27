import 'dart:math';

import 'stock_reference_model.dart';

/// Generador de secuencias adversas para property-based testing.
class StockSequenceGenerator {
  StockSequenceGenerator(this.rng, {this.productos = const ['A', 'B', 'C']});

  final Random rng;
  final List<String> productos;

  int _seq = 0;

  String _nextEventId(String kind) {
    _seq++;
    return '$kind:$_seq';
  }

  List<StockCertEvent> generate({
    required int length,
    bool includeNetwork = true,
    bool includeCrash = true,
    bool includePoison = false,
  }) {
    final events = <StockCertEvent>[];
    final liveOps = <({String eventId, String codigo, int delta})>[];

    for (var i = 0; i < length; i++) {
      final roll = rng.nextInt(100);
      if (roll < 35) {
        // Movimiento comercial
        final kind = switch (rng.nextInt(4)) {
          0 => 'venta',
          1 => 'compra',
          2 => 'remito',
          _ => 'ajuste',
        };
        final codigo = productos[rng.nextInt(productos.length)];
        var delta = rng.nextInt(5) + 1;
        if (kind == 'venta' || kind == 'remito') delta = -delta;
        if (kind == 'ajuste' && rng.nextBool()) delta = -delta;
        final eventId = _nextEventId(kind);
        events.add(LocalApply(
          eventId: eventId,
          codigo: codigo,
          delta: delta,
          documentType: kind,
        ));
        liveOps.add((eventId: eventId, codigo: codigo, delta: delta));
      } else if (roll < 50 && liveOps.isNotEmpty) {
        // Replay / retry del mismo eventId
        final op = liveOps[rng.nextInt(liveOps.length)];
        events.add(LocalReplay(
          eventId: op.eventId,
          codigo: op.codigo,
          delta: op.delta,
        ));
      } else if (roll < 62 && liveOps.isNotEmpty) {
        // Remote replay (peer) del opId
        final op = liveOps[rng.nextInt(liveOps.length)];
        events.add(RemoteApply(
          opId: '${op.eventId}_${op.codigo}',
          codigo: op.codigo,
          delta: op.delta,
        ));
      } else if (includeNetwork && roll < 75) {
        events.add(UploadAttempt(writerId: rng.nextBool() ? 'w1' : 'w2'));
        if (rng.nextBool() && liveOps.isNotEmpty) {
          final op = liveOps[rng.nextInt(liveOps.length)];
          events.add(AckIfApplied(opId: '${op.eventId}_${op.codigo}'));
        }
      } else if (includeNetwork && roll < 82) {
        events.add(rng.nextBool() ? const GoOffline() : const GoOnline());
      } else if (includeCrash && roll < 90) {
        events.add(
          rng.nextBool()
              ? const CrashAfterCommit()
              : const CrashBeforeCommit(),
        );
      } else if (includePoison && liveOps.isNotEmpty && roll < 93) {
        final op = liveOps[rng.nextInt(liveOps.length)];
        events.add(PoisonOutbox(opId: '${op.eventId}_${op.codigo}'));
      } else if (liveOps.isNotEmpty) {
        // Operaciones fuera de orden: remote apply de op vieja
        final op = liveOps[rng.nextInt(liveOps.length)];
        events.add(RemoteApply(
          opId: '${op.eventId}_${op.codigo}',
          codigo: op.codigo,
          delta: op.delta,
        ));
      } else {
        events.add(LocalApply(
          eventId: _nextEventId('ajuste'),
          codigo: productos.first,
          delta: 1,
        ));
      }
    }
    // Drenaje final: online + uploads + acks
    events.add(const GoOnline());
    for (var i = 0; i < liveOps.length + 3; i++) {
      events.add(const UploadAttempt(writerId: 'drain'));
    }
    for (final op in liveOps) {
      events.add(AckIfApplied(opId: '${op.eventId}_${op.codigo}'));
    }
    return events;
  }
}

/// Serializa secuencia para reproducir contraejemplos.
String encodeSequence(List<StockCertEvent> events) {
  final buf = StringBuffer();
  for (final e in events) {
    buf.writeln(switch (e) {
      LocalApply(:final eventId, :final codigo, :final delta, :final documentType) =>
        'LOCAL|$documentType|$eventId|$codigo|$delta',
      LocalReplay(:final eventId, :final codigo, :final delta) =>
        'REPLAY|$eventId|$codigo|$delta',
      RemoteApply(:final opId, :final codigo, :final delta) =>
        'REMOTE|$opId|$codigo|$delta',
      UploadAttempt(:final opId, :final writerId) =>
        'UPLOAD|${opId ?? ''}|$writerId',
      AckIfApplied(:final opId) => 'ACK|$opId',
      GoOffline() => 'OFF',
      GoOnline() => 'ON',
      CrashBeforeCommit() => 'CRASH_BEFORE',
      CrashAfterCommit() => 'CRASH_AFTER',
      PoisonOutbox(:final opId) => 'POISON|$opId',
    });
  }
  return buf.toString();
}
