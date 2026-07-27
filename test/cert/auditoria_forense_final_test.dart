import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';

/// Contraejemplos de la auditoría forense final (evidencia de bugs hallados).
/// Los P0 corregidos se documentan aquí como "resistido tras fix".
void main() {
  group('Forense final — reglas de watermark anti-pérdida', () {
    test('malformed contado como blocker: sin park NO avanza', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 1,
          skippedMissingProduct: 0,
          skippedPendingApply: 1, // malformed mapped as pending-like
          blockersParkedInHolds: false,
        ),
        isFalse,
      );
    });

    test('malformed parked → avanza (no HOL eterno)', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 1,
          skippedMissingProduct: 0,
          skippedPendingApply: 1,
          blockersParkedInHolds: true,
        ),
        isTrue,
      );
    });
  });
}
