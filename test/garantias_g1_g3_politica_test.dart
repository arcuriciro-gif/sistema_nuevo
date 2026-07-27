import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_ack_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_windows_apply_protocol.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_windows_policy.dart';

/// Demostración formal de políticas G1/G3 (sin Firebase).
void main() {
  group('G1 — status=applied es terminal (no re-increment)', () {
    test('applied → appliedComplete; needsIncrement=false', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'applied',
        ultimaStockOpProducto: 'otra',
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.appliedComplete);
      expect(stockOpNeedsIncrement(p), isFalse);
    });

    test('Windows: applied → done (sin increment)', () {
      final step = decideWindowsStockOpAfterRead(
        const WindowsStockOpSnapshot(
          exists: true,
          status: 'applied',
          incrementApplied: true,
          claim: 'x',
        ),
      );
      expect(step, WindowsStockOpStep.done);
      expect(windowsStepMayIncrement(step), isFalse);
    });

    test('Windows: incrementApplied sin applied → solo seal', () {
      final step = decideWindowsStockOpAfterRead(
        const WindowsStockOpSnapshot(
          exists: true,
          status: 'claimed',
          incrementApplied: true,
          claim: 'x',
        ),
      );
      expect(step, WindowsStockOpStep.sealAppliedOnly);
      expect(windowsStepMayIncrement(step), isFalse);
    });
  });

  group('G1 — claim exclusivo: solo un writer incrementa', () {
    test('tras claim propio → incrementAndSeal', () {
      final step = decideWindowsStockOpAfterClaim(
        snap: const WindowsStockOpSnapshot(
          exists: true,
          status: 'claimed',
          incrementApplied: false,
          claim: 'mine',
        ),
        ourClaim: 'mine',
      );
      expect(step, WindowsStockOpStep.incrementAndSeal);
      expect(windowsStepMayIncrement(step), isTrue);
    });

    test('tras claim perdido → retryLater (no increment, no ACK)', () {
      final step = decideWindowsStockOpAfterClaim(
        snap: const WindowsStockOpSnapshot(
          exists: true,
          status: 'claimed',
          incrementApplied: false,
          claim: 'other',
        ),
        ourClaim: 'mine',
      );
      expect(step, WindowsStockOpStep.retryLater);
      expect(windowsStepMayIncrement(step), isFalse);
    });

    test('simulación concurrente: último claim gana; perdedor no incrementa', () {
      // Modelo: dos writers A y B sobre pending. Último claim gana.
      var snap = const WindowsStockOpSnapshot(
        exists: true,
        status: 'pending_apply',
        incrementApplied: false,
        claim: null,
      );
      expect(
        decideWindowsStockOpAfterRead(snap),
        WindowsStockOpStep.claimExisting,
      );

      // A escribe claim=A
      snap = const WindowsStockOpSnapshot(
        exists: true,
        status: 'claimed',
        incrementApplied: false,
        claim: 'A',
      );
      // B escribe claim=B (pisa)
      snap = const WindowsStockOpSnapshot(
        exists: true,
        status: 'claimed',
        incrementApplied: false,
        claim: 'B',
      );

      expect(
        decideWindowsStockOpAfterClaim(snap: snap, ourClaim: 'A'),
        WindowsStockOpStep.retryLater,
      );
      expect(
        decideWindowsStockOpAfterClaim(snap: snap, ourClaim: 'B'),
        WindowsStockOpStep.incrementAndSeal,
      );
      // Solo B puede incrementar → a lo sumo un increment.
    });
  });

  group('G3 — ACK solo con cloud proof', () {
    test('sin proof → false', () {
      expect(mayAckStockOpWithoutCloudProof(), isFalse);
      expect(mayAckStockOp(cloudAppliedProven: false), isFalse);
    });

    test('con proof → true', () {
      expect(mayAckStockOp(cloudAppliedProven: true), isTrue);
    });

    test('payload vacío no es ejecutable', () {
      expect(
        stockOpOutboxPayloadExecutable(payloadRaw: null, remoteOpId: 'x'),
        isFalse,
      );
      expect(
        stockOpOutboxPayloadExecutable(payloadRaw: '', remoteOpId: 'x'),
        isFalse,
      );
      expect(
        stockOpOutboxPayloadExecutable(
          payloadRaw: '{"opId":"a","codigo":"P","delta":1}',
          remoteOpId: 'a',
        ),
        isTrue,
      );
    });
  });
}
