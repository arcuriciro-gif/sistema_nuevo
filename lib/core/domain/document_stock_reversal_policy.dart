/// Política pura anular/restaurar stock de documentos comerciales.
///
/// Cubre el caso seguidor: el stock llegó vía `stock_ops` atribuidos como
/// `stock_op` (legado sin documentType) → `ledgerNet(remito|venta) == 0`
/// aunque el stock físico ya bajó. En ese caso hay que revertir al anular
/// **solo** si el documento es de entrega (`treatZeroNetAsDelivered`).
///
/// Facturas A/B/C no entregan: `treatZeroNetAsDelivered=false` → anular con
/// `net==0` NO inventa stock.
///
/// Al restaurar, si el neto del documento ya es entrega activa (`net < 0`),
/// NO re-entregar (evita doble aplicación).
class DocumentStockReversalPolicy {
  DocumentStockReversalPolicy._();

  /// ¿Revertir mercadería al anular?
  ///
  /// - [ledgerNet] < 0: hubo entrega atribuida al documento → sí
  /// - [ledgerNet] == 0 + [treatZeroNetAsDelivered]: seguidor legado de
  ///   documento que entrega (remito / nota_entrega) → sí
  /// - [ledgerNet] > 0: ya revertido → no
  static bool shouldReverseOnAnular({
    required int ledgerNet,
    required bool hasLines,
    bool treatZeroNetAsDelivered = false,
  }) {
    if (!hasLines) return false;
    if (ledgerNet < 0) return true;
    if (ledgerNet == 0 && treatZeroNetAsDelivered) return true;
    return false;
  }

  /// ¿Re-entregar mercadería al restaurar un documento anulado?
  ///
  /// Solo si no hay entrega neta activa bajo el documento (`net >= 0`).
  static bool shouldRedeliverOnRestore({
    required int ledgerNet,
    required bool hasLines,
  }) {
    if (!hasLines) return false;
    return ledgerNet >= 0;
  }
}
