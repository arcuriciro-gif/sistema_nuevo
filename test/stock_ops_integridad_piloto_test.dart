import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/domain/document_stock_reversal_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_ack_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_windows_policy.dart';

void main() {
  group('C1 Windows stock_ops phase machine', () {
    test('missing → needs increment', () {
      final p = classifyStockOpCloud(
        exists: false,
        status: null,
        ultimaStockOpProducto: null,
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.missing);
      expect(stockOpNeedsIncrement(p), isTrue);
    });

    test('applied sin ultimaStockOp → appliedComplete (idempotencia por op)', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'applied',
        ultimaStockOpProducto: 'otra',
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.appliedComplete);
      expect(stockOpNeedsIncrement(p), isFalse);
    });

    test('applied + ultimaStockOp → complete, no re-increment', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'applied',
        ultimaStockOpProducto: 'op1',
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.appliedComplete);
      expect(stockOpNeedsIncrement(p), isFalse);
    });

    test('pending_apply → needs increment', () {
      final p = classifyStockOpCloud(
        exists: true,
        status: 'pending_apply',
        ultimaStockOpProducto: null,
        opId: 'op1',
      );
      expect(p, StockOpCloudPhase.pendingApply);
      expect(stockOpNeedsIncrement(p), isTrue);
    });
  });

  group('C4 watermark no salta ops con producto ausente', () {
    test('con skips NO avanza', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 3,
          skippedMissingProduct: 1,
        ),
        isFalse,
      );
    });

    test('sin skips avanza', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 3,
          skippedMissingProduct: 0,
        ),
        isTrue,
      );
    });

    test('página vacía puede avanzar', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 0,
          skippedMissingProduct: 0,
        ),
        isTrue,
      );
    });

    test('truncate por maxApply NO avanza', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 4,
          skippedMissingProduct: 0,
          truncatedByMaxApply: true,
        ),
        isFalse,
      );
    });

    test('pending_apply en página NO avanza', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 0,
          skippedMissingProduct: 0,
          skippedPendingApply: 2,
        ),
        isFalse,
      );
    });

    test('pending_apply parked NO avanza (anti divergencia stock)', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 0,
          skippedMissingProduct: 0,
          skippedPendingApply: 2,
          blockersParkedInHolds: true,
        ),
        isFalse,
      );
    });

    test('missing_product parked SÍ avanza (anti-HOL recoverable)', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 0,
          skippedMissingProduct: 2,
          skippedPendingApply: 0,
          blockersParkedInHolds: true,
        ),
        isTrue,
      );
    });
  });

  group('C2 document meta en stock_ops', () {
    test('con meta comercial se conserva', () {
      final m = resolveStockOpDocumentMeta(
        opId: 'op-x',
        documentType: 'remito',
        documentId: '42',
      );
      expect(m.documentType, 'remito');
      expect(m.documentId, '42');
    });

    test('sin meta → legado stock_op/opId', () {
      final m = resolveStockOpDocumentMeta(opId: 'op-x');
      expect(m.documentType, 'stock_op');
      expect(m.documentId, 'op-x');
    });
  });

  group('C2/C3 anular/restaurar seguidor', () {
    test('anular: net<0 revierte', () {
      expect(
        DocumentStockReversalPolicy.shouldReverseOnAnular(
          ledgerNet: -5,
          hasLines: true,
        ),
        isTrue,
      );
    });

    test('anular: net==0 + treatZeroNet (remito/nota) revierte', () {
      expect(
        DocumentStockReversalPolicy.shouldReverseOnAnular(
          ledgerNet: 0,
          hasLines: true,
          treatZeroNetAsDelivered: true,
        ),
        isTrue,
      );
    });

    test('anular: net==0 factura (no entrega) NO inventa stock', () {
      expect(
        DocumentStockReversalPolicy.shouldReverseOnAnular(
          ledgerNet: 0,
          hasLines: true,
          treatZeroNetAsDelivered: false,
        ),
        isFalse,
      );
    });

    test('anular: net>0 ya revertido → no', () {
      expect(
        DocumentStockReversalPolicy.shouldReverseOnAnular(
          ledgerNet: 5,
          hasLines: true,
          treatZeroNetAsDelivered: true,
        ),
        isFalse,
      );
    });

    test('restaurar: net>=0 re-entrega', () {
      expect(
        DocumentStockReversalPolicy.shouldRedeliverOnRestore(
          ledgerNet: 0,
          hasLines: true,
        ),
        isTrue,
      );
    });

    test('restaurar: net<0 NO doble entrega', () {
      expect(
        DocumentStockReversalPolicy.shouldRedeliverOnRestore(
          ledgerNet: -3,
          hasLines: true,
        ),
        isFalse,
      );
    });
  });

  group('C6 ACK stock_op solo con prueba', () {
    test('sin prueba nunca ACK', () {
      expect(mayAckStockOpWithoutCloudProof(), isFalse);
      expect(mayAckStockOp(cloudAppliedProven: false), isFalse);
    });

    test('con prueba ACK', () {
      expect(mayAckStockOp(cloudAppliedProven: true), isTrue);
    });
  });
}
