import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_ack_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_windows_policy.dart';

void main() {
  group('Forense 1.4.5 — idempotencia por op (no ultimaStockOp)', () {
    test('status=applied es terminal aunque ultimaStockOp sea otra', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'applied',
        ultimaStockOpProducto: 'op_nueva',
        opId: 'op_vieja',
      );
      expect(p, StockOpCloudPhase.appliedComplete);
      expect(stockOpNeedsIncrement(p), isFalse);
    });

    test('status=applied + ultima coincidente → complete', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'applied',
        ultimaStockOpProducto: 'op1',
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.appliedComplete);
      expect(stockOpNeedsIncrement(p), isFalse);
    });

    test('pending_apply necesita increment', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'pending_apply',
        ultimaStockOpProducto: null,
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.pendingApply);
      expect(stockOpNeedsIncrement(p), isTrue);
    });

    test('missing necesita increment', () {
      final p = classifyStockOpCloud(
        exists: false,
        status: null,
        ultimaStockOpProducto: null,
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.missing);
      expect(stockOpNeedsIncrement(p), isTrue);
    });

    test('ACK policy exige cloud proof', () {
      expect(mayAckStockOpWithoutCloudProof(), isFalse);
      expect(mayAckStockOp(cloudAppliedProven: false), isFalse);
      expect(mayAckStockOp(cloudAppliedProven: true), isTrue);
    });
  });
}
