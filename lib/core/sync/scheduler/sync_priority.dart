/// Prioridad del scheduler de sincronización (menor número = más urgente).
class SyncPriority {
  SyncPriority._();

  /// Ventas, remitos, stock_ops, cobranzas, CC.
  static const int critical = 10;

  /// Clientes / proveedores (alta comercial).
  static const int high = 20;

  /// Producto individual editado por usuario.
  static const int normal = 50;

  /// Importaciones, masivos, media, branding, mantenimiento.
  static const int background = 80;

  static int forEntityType(String entityType) {
    switch (entityType) {
      case 'venta':
      case 'remito':
      case 'stock_op':
      case 'compra':
        return critical;
      case 'cliente':
      case 'proveedor':
        return high;
      case 'producto':
        return normal;
      case 'media':
      case 'branding':
      case 'import':
      case 'mantenimiento':
        return background;
      default:
        return normal;
    }
  }

  /// ¿La entidad es cola crítica (nunca detrás de import masivo)?
  static bool isCriticalEntity(String entityType) {
    switch (entityType) {
      case 'venta':
      case 'remito':
      case 'stock_op':
      case 'compra':
      case 'cliente':
      case 'proveedor':
        return true;
      default:
        return false;
    }
  }

  /// ¿Se puede coalescer (último gana) sin romper integridad?
  /// Nunca: ventas/remitos/compras/stock_ops/cobranzas.
  static bool canCoalesce(String entityType, String operation) {
    if (operation != 'upsert') return false;
    switch (entityType) {
      case 'producto':
      case 'cliente':
      case 'proveedor':
      case 'branding':
        return true;
      default:
        return false;
    }
  }
}

/// Carriles lógicos del scheduler.
enum SyncLane {
  critical,
  background;

  String get wireName => name;

  static SyncLane forEntityType(String entityType) =>
      SyncPriority.isCriticalEntity(entityType)
          ? SyncLane.critical
          : SyncLane.background;
}
