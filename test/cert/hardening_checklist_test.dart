import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/security/admin_access_policy.dart';
import 'package:sistema_nuevo/core/sync/stable_document_id.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Hardening — identidad global', () {
    test('numero gana sobre localId', () {
      expect(
        stableCommercialDocumentId(numero: 'R-100', localId: 7),
        'R-100',
      );
    });

    test('fallback prefijo si sin numero', () {
      expect(
        stableCommercialDocumentId(
          numero: '',
          localId: 7,
          fallbackPrefix: 'R_',
        ),
        'R_7',
      );
    });

    test('candidates incluyen numero + local (legado)', () {
      expect(
        ledgerDocumentIdCandidates(numero: 'V-1', localId: 9),
        ['V-1', '9'],
      );
    });
  });

  group('Hardening — watermark', () {
    test('blockers sin park → no advance', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 3,
          skippedMissingProduct: 1,
          skippedPendingApply: 2,
          blockersParkedInHolds: false,
        ),
        isFalse,
      );
    });

    test('todos parked → advance', () {
      expect(
        shouldAdvanceStockOpsWatermark(
          consideredValid: 3,
          skippedMissingProduct: 1,
          skippedPendingApply: 2,
          blockersParkedInHolds: true,
        ),
        isTrue,
      );
    });
  });

  group('Hardening — admin123 default OFF', () {
    test('sin key persistida → recovery deshabilitado', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AdminAccessPolicy.instance.isDefaultRecoveryEnabled(), isFalse);
    });

    test('bootstrap enable → ON', () async {
      SharedPreferences.setMockInitialValues({});
      await AdminAccessPolicy.instance.enableDefaultRecoveryForBootstrap();
      expect(await AdminAccessPolicy.instance.isDefaultRecoveryEnabled(), isTrue);
    });
  });
}
