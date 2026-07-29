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
  ///
  /// Campo: maxApply ≥50 tumbaba el EXE. Techo duro **4**.
  /// `recentLimit` NUNCA es 0: sin pull reciente, watermark adelantado
  /// deja stock divergente (EXE↔APK).
  static const int stockOpsHardCap = 4;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 10,
        maxApply: stockOpsHardCap,
        recentLimit: 20,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: 3,
        recentLimit: 15,
      );
    }
    return (
      maxPages: 1,
      pageSize: 8,
      maxApply: 2,
      recentLimit: 12,
    );
  }

  /// Soft-pull lane.
  ///
  /// Con [prioritizeStockOps] (outbox quieto):
  ///   remitos / ventas / stock_ops / compras en rotación densa.
  /// Con cola de productos (WhatsApp/listas / import):
  ///   **1 de cada 3 ticks = stock_ops** (antes ~1/30 → stock diverge horas).
  ///   1/3 productos, 1/3 resto. Campo: lista WhatsApp ahogaba deltas.
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
    // Busy: stock_ops NUNCA se ahoga detrás de productos.
    if (n % 3 == 0) return 'stock_ops';
    if (n % 3 == 1) {
      return (n ~/ 3).isEven ? 'productos_inc' : 'productos_cat';
    }
    final others = softPullOtherLanes
        .where((l) => l != 'stock_ops')
        .toList(growable: false);
    return others[(n ~/ 3) % others.length];
  }

  /// Intervalo del pump dedicado de stock_ops en Windows (anti-starvation).
  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 30);

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

  /// Presupuesto de "Actualizar ahora" en Windows.
  ///
  /// Campo 1.4.12: la ráfaga negocio+clientes+stock+drain en un solo gesto
  /// seguía tumbando el .exe. Ahora: **stock primero**, micro-rondas con
  /// yield, negocio mínimo, sin página grande de clientes.
  ///
  /// `stockMaxApply` nunca supera [stockOpsHardCap] (misma causa raíz).
  static ({
    int negocioLimit,
    int clientesPage,
    int stockMaxPages,
    int stockPageSize,
    int stockMaxApply,
    int stockRecentLimit,
    int stockRounds,
    int stockMicroBatch,
    int yieldMs,
    int schedulerTicks,
    bool pullClientes,
    bool pullConfig,
  }) manualRefreshBudgetWindows({required int pendingProductos}) {
    // Anti-crash: maxApply por ronda ≤ hardCap + más rondas + recentLimit.
    // Subir maxApply a 50 tumbaba el .exe (regresión vs 1.4.12).
    if (pendingProductos >= 50) {
      return (
        negocioLimit: 5,
        clientesPage: 0,
        stockMaxPages: 1,
        stockPageSize: 12,
        stockMaxApply: stockOpsHardCap,
        stockRecentLimit: 25,
        stockRounds: 5,
        stockMicroBatch: 2,
        yieldMs: 220,
        schedulerTicks: 1,
        pullClientes: false,
        pullConfig: false,
      );
    }
    if (pendingProductos >= 10) {
      return (
        negocioLimit: 8,
        clientesPage: 0,
        stockMaxPages: 2,
        stockPageSize: 15,
        stockMaxApply: stockOpsHardCap,
        stockRecentLimit: 35,
        stockRounds: 5,
        stockMicroBatch: 2,
        yieldMs: 180,
        schedulerTicks: 1,
        pullClientes: false,
        pullConfig: true,
      );
    }
    return (
      negocioLimit: 10,
      clientesPage: 0,
      stockMaxPages: 2,
      stockPageSize: 15,
      stockMaxApply: stockOpsHardCap,
      stockRecentLimit: 40,
      stockRounds: 5,
      stockMicroBatch: 3,
      yieldMs: 140,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: true,
    );
  }

  /// Catch-up inicial Windows: suficiente para converger sin ráfaga letal.
  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 10, maxApply: stockOpsHardCap);

  /// Plan de drain del outbox Windows (scheduler v2).
  ///
  /// **Crítico primero:** ventas/remitos/stock/clientes nunca esperan detrás
  /// de miles de productos de importación. El fondo (productos) solo corre
  /// con cupo residual o cuando no hay críticos.
  static List<({List<String> types, int claim})> outboxDrainPlan({
    required Map<String, int> breakdown,
    required int tick,
  }) {
    final nCritDocs = (breakdown['venta'] ?? 0) +
        (breakdown['remito'] ?? 0) +
        (breakdown['compra'] ?? 0) +
        (breakdown['cliente'] ?? 0) +
        (breakdown['proveedor'] ?? 0);
    final nStock = breakdown['stock_op'] ?? 0;
    final nProd = breakdown['producto'] ?? 0;
    final plan = <({List<String> types, int claim})>[];

    if (nCritDocs > 0) {
      plan.add((
        types: const ['venta', 'remito', 'compra', 'cliente', 'proveedor'],
        claim: nCritDocs.clamp(1, 10),
      ));
    }
    if (nStock > 0) {
      plan.add((
        types: const ['stock_op'],
        claim: nStock.clamp(1, 8),
      ));
    }
    // Fondo: solo si no hay críticos, o cupo mínimo residual.
    if (nProd > 0) {
      final bgClaim = (nCritDocs + nStock) == 0
          ? nProd.clamp(1, 6)
          : 1;
      plan.add((
        types: const ['producto'],
        claim: bgClaim,
      ));
    }
    // tick se conserva por compat API / métricas de rotación.
    if (plan.isEmpty && tick >= 0) {
      return plan;
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
