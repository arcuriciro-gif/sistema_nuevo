/// Política oficial de entrega de mercadería (Sprint integridad inventario).
///
/// **Opción B — Remito entrega; Factura documenta.**
///
/// | Documento | ¿Mueve stock? |
/// |---|---|
/// | Remito (salida) | Sí |
/// | Nota de entrega / comprobante interno | Sí |
/// | Factura A / B / C | No (fiscal + cuenta corriente) |
/// | Presupuesto | No |
/// | Compra confirmada | Sí (recepción) |
/// | Ajuste de inventario | Sí (único camino para stock manual) |
///
/// Consecuencia: es imposible descontar dos veces la misma operación
/// física vía Remito + Factura, porque la factura no entrega.
///
/// La venta rápida del sistema emite **Remito**, que es el canal de stock.
///
/// Ciclos anular↔restaurar usan eventIds con revision (microseconds) para
/// no chocar con la idempotencia del ledger.
class InventoryDeliveryPolicy {
  InventoryDeliveryPolicy._();

  /// ¿Una venta/factura de tipo [tipo] entrega mercadería?
  static bool ventaMueveStock(String tipo) {
    switch (tipo) {
      case 'nota_entrega':
      case 'comprobante_interno':
        return true;
      case 'factura_a':
      case 'factura_b':
      case 'factura_c':
      case 'presupuesto':
        return false;
      default:
        // Tipos desconocidos: no entregan (fail-safe).
        return false;
    }
  }

  /// Event id canónico de entrega al crear venta (una sola vez por alta).
  static String eventIdEntregaVenta(int ventaId) => 'inv:entrega:venta:$ventaId';

  /// Reverso de entrega (ciclo anular; [rev] evita colisión tras restaurar).
  static String eventIdEntregaRevVenta(int ventaId, {required int rev}) =>
      'inv:entrega_rev:venta:$ventaId:$rev';

  /// Re-entrega al restaurar una venta anulada.
  static String eventIdEntregaRestoreVenta(int ventaId, {required int rev}) =>
      'inv:entrega:venta:$ventaId:restore:$rev';

  static String eventIdRecepcionCompra(int compraId) =>
      'inv:recepcion:compra:$compraId';

  static String eventIdRecepcionRevCompra(int compraId, {required int rev}) =>
      'inv:recepcion_rev:compra:$compraId:$rev';

  static String eventIdRecepcionReopenCompra(int compraId, {required int rev}) =>
      'inv:recepcion:compra:$compraId:reopen:$rev';
}
