/// Watermark de pull stock_ops: orden temporal por `at` (`at_v2`).
///
/// El watermark viejo (solo `afterDocId` UUID) no es orden temporal: se
/// reinicia para no perder ops nuevas en el APK.
({String afterId, String afterAt}) migrateStockOpsWatermark(
  Map<String, dynamic> meta,
) {
  var afterId = meta['afterDocId']?.toString() ?? '';
  var afterAt = meta['afterAt']?.toString() ?? '';
  if (afterAt.isEmpty &&
      afterId.isNotEmpty &&
      meta['v']?.toString() != 'at_v2') {
    afterId = '';
    afterAt = '';
  }
  return (afterId: afterId, afterAt: afterAt);
}
