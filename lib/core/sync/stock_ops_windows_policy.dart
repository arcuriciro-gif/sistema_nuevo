/// Política pura del camino stock_ops (sin Firebase).
///
/// Idempotencia = estado **por op** en `stock_ops/{opId}.status`.
/// NUNCA usar `productos.ultimaStockOp` como prueba de ops históricas:
/// una op posterior pisa ese campo y las anteriores parecen "incompletas"
/// → re-increment / stock duplicado (auditoría forense 1.4.5).
enum StockOpCloudPhase {
  /// No existe el doc.
  missing,

  /// Claim / pendiente; falta confirmar increment + status applied.
  pendingApply,

  /// @Deprecated — conservado por compat tests; classify ya no lo emite.
  appliedIncomplete,

  /// status == applied → terminal. No re-incrementar jamás.
  appliedComplete,
}

/// Clasifica el estado de una stock_op en nube.
///
/// [ultimaStockOpProducto] se ignora a propósito (API legacy). La prueba
/// de apply es únicamente `status == applied` en el doc de la op.
StockOpCloudPhase classifyStockOpCloud({
  required bool exists,
  required String? status,
  String? ultimaStockOpProducto,
  required String opId,
}) {
  if (!exists) return StockOpCloudPhase.missing;
  final st = (status ?? '').trim();
  // Terminal: applied es irrevocable por opId (idempotencia fuerte).
  if (st == 'applied') {
    return StockOpCloudPhase.appliedComplete;
  }
  if (st == 'pending_apply' || st == 'claimed' || st.isEmpty) {
    return StockOpCloudPhase.pendingApply;
  }
  // Estados desconocidos: tratar como pendiente (no como applied).
  return StockOpCloudPhase.pendingApply;
}

/// ¿Hay que ejecutar FieldValue.increment?
bool stockOpNeedsIncrement(StockOpCloudPhase phase) {
  switch (phase) {
    case StockOpCloudPhase.missing:
    case StockOpCloudPhase.pendingApply:
    case StockOpCloudPhase.appliedIncomplete:
      return true;
    case StockOpCloudPhase.appliedComplete:
      return false;
  }
}
