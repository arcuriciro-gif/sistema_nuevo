// Políticas puras del pull de stock_ops (watermark / skips / HOL).

/// Reglas de avance del watermark stock_ops:
///
/// - Truncado por maxApply → NO avanzar.
/// - `pending_apply` / `claimed` en página → **NO avanzar** (aunque estén
///   en hold-set). Si se avanza, el peer pierde las ops y el stock diverge
///   (EXE=-2 / APK=0). El reconcile debe pasarlas a `applied` primero.
/// - Solo `missing_product` parked en holds → SÍ avanzar (anti-HOL).
///   El sweeper aplica cuando llega el SKU al catálogo.
/// - Sin blockers → avanzar.
bool shouldAdvanceStockOpsWatermark({
  required int consideredValid,
  required int skippedMissingProduct,
  int skippedPendingApply = 0,
  bool truncatedByMaxApply = false,
  /// Blockers (missing) ya persistidos en hold-set.
  bool blockersParkedInHolds = false,
}) {
  if (truncatedByMaxApply) return false;
  // Regresión P0: jamás saltar pending_apply (stock diverge permanente).
  if (skippedPendingApply > 0) return false;
  if (skippedMissingProduct > 0) {
    // Anti-HOL solo para producto ausente (recoverable vía catalog+sweep).
    return blockersParkedInHolds;
  }
  if (consideredValid == 0 && skippedMissingProduct == 0) {
    return true;
  }
  return true;
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
