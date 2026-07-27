// Políticas puras del pull de stock_ops (watermark / skips).

/// Si en la página hubo ops válidas saltadas por producto ausente,
/// pending_apply, o truncado por maxApply, NO avanzar el watermark
/// (si no, el movimiento se pierde para siempre → stock diverge EXE↔APK).
bool shouldAdvanceStockOpsWatermark({
  required int consideredValid,
  required int skippedMissingProduct,
  int skippedPendingApply = 0,
  bool truncatedByMaxApply = false,
}) {
  if (truncatedByMaxApply) return false;
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
