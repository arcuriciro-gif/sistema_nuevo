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

  /// Event id canónico de entrega por venta (para anular/revertir legado).
  static String eventIdEntregaVenta(int ventaId) => 'inv:entrega:venta:$ventaId';

  static String eventIdEntregaRevVenta(int ventaId) =>
      'inv:entrega_rev:venta:$ventaId';
}
