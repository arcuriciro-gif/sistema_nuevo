/// Política pura del camino Windows de stock_ops (sin Firebase).
///
/// Evita: crear op como `applied` y salir antes del increment → ACK con
/// stock de nube incorrecto.
enum StockOpCloudPhase {
  /// No existe el doc.
  missing,

  /// Claim creado; falta confirmar increment en producto.
  pendingApply,

  /// Marca applied pero producto.ultimaStockOp ≠ opId (crash mid-write).
  appliedIncomplete,

  /// Completamente aplicada.
  appliedComplete,
}

StockOpCloudPhase classifyStockOpCloud({
  required bool exists,
  required String? status,
  required String? ultimaStockOpProducto,
  required String opId,
}) {
  if (!exists) return StockOpCloudPhase.missing;
  final st = (status ?? '').trim();
  if (st == 'pending_apply' || st == 'claimed') {
    return StockOpCloudPhase.pendingApply;
  }
  if (st == 'applied' || st.isEmpty) {
    if (ultimaStockOpProducto == opId) {
      return StockOpCloudPhase.appliedComplete;
    }
    return StockOpCloudPhase.appliedIncomplete;
  }
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
