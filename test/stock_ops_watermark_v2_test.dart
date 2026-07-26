import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_watermark.dart';

void main() {
  group('stock_ops watermark at_v2', () {
    test('watermark legacy solo-docId se reinicia', () {
      final m = migrateStockOpsWatermark({
        'afterDocId': 'uuid-zzzz-old',
      });
      expect(m.afterId, isEmpty);
      expect(m.afterAt, isEmpty);
    });

    test('watermark at_v2 se conserva', () {
      final m = migrateStockOpsWatermark({
        'v': 'at_v2',
        'afterDocId': 'op-123',
        'afterAt': '2026-07-10T12:00:00.000Z',
      });
      expect(m.afterId, 'op-123');
      expect(m.afterAt, '2026-07-10T12:00:00.000Z');
    });

    test('watermark vacío no se toca', () {
      final m = migrateStockOpsWatermark({});
      expect(m.afterId, isEmpty);
      expect(m.afterAt, isEmpty);
    });
  });
}
