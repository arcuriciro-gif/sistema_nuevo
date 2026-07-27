/// Política de sync en Windows desktop: cuarentena al login + sync eventual.
///
/// Prioridad: que el .exe no se caiga. La sync converge después, sin ráfagas.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: solo absorber outbox local; sin Firebase de colección.
  static const Duration quarantineAfterLogin = Duration(seconds: 20);

  /// Si hay mucha cola de productos, acortar cuarentena (no dejar
  /// "arranque 45s" con 500 pending y 0 intentos).
  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 10);
    if (pendingProductos >= 10) return const Duration(seconds: 15);
    return quarantineAfterLogin;
  }

  /// Delay entre jobs normales del throttle (outbox/pull).
  static const Duration throttleDelayNormal = Duration(milliseconds: 600);

  /// Delay corto para acción de usuario (1 producto / remito / cliente).
  /// Objetivo: reflejar en el otro dispositivo en segundos, no minutos.
  static const Duration throttleDelayInteractive = Duration(milliseconds: 50);

  /// Outbox pump (tras cuarentena): micro-lotes más frecuentes.
  static const Duration outboxPumpInterval = Duration(seconds: 25);

  /// Soft-pull: convergencia catálogo/stock (no sustituye listeners de negocio).
  static const Duration softPullInterval = Duration(seconds: 60);

  /// Listeners Firestore en Windows SOLO para colecciones chicas de negocio.
  /// Productos/branding/Storage siguen OFF (eran los que tumbaban el .exe).
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  /// Reclaim inflight huérfanos tras crash.
  static const Duration reclaimStaleInflightAfter = Duration(minutes: 3);

  /// Lanes del soft-pull (no-productos). Incluye config texto (sin Storage).
  static const List<String> softPullOtherLanes = [
    'clientes',
    'ventas',
    'remitos',
    'stock_ops',
    'compras',
    'proveedores',
    'listas',
    'categorias',
    'permisos',
    'branding_text',
  ];

  /// Con cola de upload chica, priorizar convergencia de negocio + stock
  /// (remitos/ventas/stock_ops). Campo: venta rápida EXE↔APK no cruzaba.
  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  /// @Deprecated — alias de [prioritizeBusinessConvergence].
  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  /// Presupuesto de pull stock_ops en Windows (ráfagas controladas).
  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (maxPages: 2, pageSize: 30, maxApply: 24, recentLimit: 50);
    }
    if (pendingProductos <= 50) {
      return (maxPages: 1, pageSize: 15, maxApply: 8, recentLimit: 0);
    }
    // Subiendo catálogo: casi no tocar stock_ops (evita tumbar .exe).
    return (maxPages: 1, pageSize: 10, maxApply: 4, recentLimit: 0);
  }

  /// Soft-pull lane.
  ///
  /// Con [prioritizeStockOps]/convergencia de negocio):
  ///   remitos / ventas / stock_ops / compras en rotación densa.
  /// Sin eso: ~33% productos, resto round-robin.
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    if (prioritizeStockOps) {
      // Ciclo de 6: negocio primero (campo venta rápida EXE↔APK).
      switch (n % 6) {
        case 0:
          return 'remitos';
        case 1:
          return 'ventas';
        case 2:
          return 'stock_ops';
        case 3:
          return 'compras';
        case 4:
          return 'stock_ops';
        default:
          return (n ~/ 6).isEven ? 'productos_inc' : 'clientes';
      }
    }
    if (n % 3 == 0) {
      return (n ~/ 3) % 2 == 0 ? 'productos_inc' : 'productos_cat';
    }
    final otherIdx =
        ((n ~/ 3) * 2 + ((n % 3) - 1)) % softPullOtherLanes.length;
    return softPullOtherLanes[otherIdx];
  }

  /// Intervalo soft-pull más corto cuando ya no hay cola de productos.
  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 20);
    }
    return softPullInterval;
  }

  /// Cuántos docs recientes tirar por `actualizadoEn` (idempotente).
  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return 25;
    }
    return 0;
  }

  /// Plan de drain del outbox Windows: qué buckets tocar este tick.
  ///
  /// Si hay productos pendientes, SIEMPRE van primero (antes un tick
  /// compartido con soft-pull quedaba en 0 y nunca los subía).
  static List<({List<String> types, int claim})> outboxDrainPlan({
    required Map<String, int> breakdown,
    required int tick,
  }) {
    final nProd = breakdown['producto'] ?? 0;
    final nProv = breakdown['proveedor'] ?? 0;
    final nDocs = (breakdown['venta'] ?? 0) +
        (breakdown['remito'] ?? 0) +
        (breakdown['compra'] ?? 0) +
        (breakdown['cliente'] ?? 0);
    final nStock = breakdown['stock_op'] ?? 0;
    final plan = <({List<String> types, int claim})>[];
    if (nProd + nProv > 0) {
      final claim = (nProd + nProv) >= 100
          ? 8
          : (nProd + nProv) >= 20
              ? 6
              : 4;
      plan.add((
        types: const ['producto', 'proveedor'],
        claim: claim,
      ));
    }
    if (nDocs > 0 || tick % 2 == 0) {
      plan.add((
        types: const ['venta', 'remito', 'compra', 'cliente'],
        claim: 4,
      ));
    }
    if (nStock > 0 || tick % 3 == 2) {
      plan.add((
        types: const ['stock_op'],
        claim: 2,
      ));
    }
    return plan;
  }

  /// En Windows el masivo (análisis de lista) solo encola outbox.
  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Storage / chat remoto / branding snapshot: off en Windows.
  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
