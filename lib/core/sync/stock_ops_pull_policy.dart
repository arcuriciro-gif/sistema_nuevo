// Políticas puras del pull de stock_ops (watermark / skips / HOL).

/// Si en la página hubo ops válidas saltadas por producto ausente,
/// pending_apply, o truncado por maxApply:
/// - **antes:** no avanzar (HOL — cursor congelado).
/// - **ahora:** si [blockersParkedInHolds] (todas las bloqueantes están en
///   `stock_ops_pull_holds`), SÍ avanzar. El sweeper reintenta holds aparte.
///
/// Nunca avanzar a ciegas sin holds (perdería ops → stock diverge).
bool shouldAdvanceStockOpsWatermark({
  required int consideredValid,
  required int skippedMissingProduct,
  int skippedPendingApply = 0,
  bool truncatedByMaxApply = false,
  /// Blockers (missing/pending) ya persistidos en hold-set.
  bool blockersParkedInHolds = false,
}) {
  if (truncatedByMaxApply) return false;
  final blockers = skippedMissingProduct + skippedPendingApply;
  if (blockers > 0 && blockersParkedInHolds) {
    return true;
  }
  if (skippedPendingApply > 0) return false;
  if (consideredValid == 0 && skippedMissingProduct == 0) {
    // Página vacía de candidatos → se puede cerrar/avanzar.
    return true;
  }
  return skippedMissingProduct == 0;
}

/// Metadatos de documento comercial embebidos en stock_ops.
({String documentType, String documentId}) resolveStockOpDocumentMeta({
  required String opId,
  String? documentType,
  String? documentId,
}) {
  final dt = (documentType ?? '').trim();
  final di = (documentId ?? '').trim();
  if (dt.isNotEmpty && di.isNotEmpty) {
    return (documentType: dt, documentId: di);
  }
  // Legacy: sin meta → aislar por opId (anular seguidor usará fallback).
  return (documentType: 'stock_op', documentId: opId);
}
