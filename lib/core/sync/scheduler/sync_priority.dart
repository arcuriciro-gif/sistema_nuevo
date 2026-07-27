/// Niveles de prioridad del Sync Engine 2.0 (menor = más urgente).
enum SyncPriorityLevel {
  /// Nivel 1 — ventas, remitos, stock, compras, CC, cobranzas. SLO <2s.
  critical(1, 10),

  /// Nivel 2 — clientes, proveedores, pedidos, pagos.
  high(2, 20),

  /// Nivel 3 — productos, listas de precio.
  normal(3, 50),

  /// Nivel 4 — media, branding, mantenimiento, import masivo.
  background(4, 80);

  const SyncPriorityLevel(this.level, this.numeric);
  final int level;
  final int numeric;

  String get wireName => name;

  static SyncPriorityLevel fromNumeric(int n) {
    if (n <= 15) return critical;
    if (n <= 30) return high;
    if (n <= 60) return normal;
    return background;
  }
}

/// Prioridad del scheduler de sincronización.
class SyncPriority {
  SyncPriority._();

  static const int critical = 10;
  static const int high = 20;
  static const int normal = 50;
  static const int background = 80;

  static SyncPriorityLevel levelForEntityType(String entityType) {
    switch (entityType) {
      case 'venta':
      case 'remito':
      case 'stock_op':
      case 'compra':
      case 'cuenta_corriente':
      case 'cobranza':
      case 'pago_cc':
        return SyncPriorityLevel.critical;
      case 'cliente':
      case 'proveedor':
      case 'pedido':
      case 'pago':
        return SyncPriorityLevel.high;
      case 'producto':
      case 'lista_precio':
        return SyncPriorityLevel.normal;
      case 'media':
      case 'branding':
      case 'import':
      case 'mantenimiento':
      case 'stats':
        return SyncPriorityLevel.background;
      default:
        return SyncPriorityLevel.normal;
    }
  }

  static int forEntityType(String entityType) =>
      levelForEntityType(entityType).numeric;

  /// Nivel 1 puro (SLO comercial). No incluye clientes/proveedores.
  static bool isLevel1(String entityType) =>
      levelForEntityType(entityType) == SyncPriorityLevel.critical;

  /// Niveles 1–2: operación comercial / alta.
  static bool isCriticalEntity(String entityType) {
    final l = levelForEntityType(entityType);
    return l == SyncPriorityLevel.critical || l == SyncPriorityLevel.high;
  }

  /// ¿Se puede coalescer (último gana) sin romper integridad?
  /// Nunca: ventas/remitos/compras/stock_ops/cobranzas/ledger/CC.
  static bool canCoalesce(String entityType, String operation) {
    if (operation != 'upsert') return false;
    switch (entityType) {
      case 'producto':
      case 'lista_precio':
      case 'cliente':
      case 'proveedor':
      case 'branding':
        return true;
      default:
        return false;
    }
  }
}

/// Carriles lógicos del scheduler (compat + turbo).
enum SyncLane {
  critical,
  high,
  normal,
  background;

  String get wireName => name;

  static SyncLane forEntityType(String entityType) {
    switch (SyncPriority.levelForEntityType(entityType)) {
      case SyncPriorityLevel.critical:
        return SyncLane.critical;
      case SyncPriorityLevel.high:
        return SyncLane.high;
      case SyncPriorityLevel.normal:
        return SyncLane.normal;
      case SyncPriorityLevel.background:
        return SyncLane.background;
    }
  }

  /// Lane wire compatible con filas antiguas (solo critical/background).
  static SyncLane fromWire(String? wire) {
    switch (wire) {
      case 'critical':
        return SyncLane.critical;
      case 'high':
        return SyncLane.high;
      case 'normal':
        return SyncLane.normal;
      case 'background':
        return SyncLane.background;
      default:
        return SyncLane.background;
    }
  }
}
