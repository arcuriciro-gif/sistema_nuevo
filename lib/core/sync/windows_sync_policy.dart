/// Política de sync en Windows desktop: modo local tranquilo.
///
/// Prioridad #1: que el .exe no se caiga.
/// Prioridad #2: lo del local — productos/precios, comprobantes, stock, pendientes.
///
/// 1.4.39: se corta el trabajo de laboratorio (soft-pull duplicado de stock_ops,
/// heal/micro-catchup agresivos). El pump unificado ya trae stock_ops; el soft-pull
/// solo actualiza catálogo/precios de a poco.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: solo absorber outbox local; sin Firebase de colección.
  static const Duration quarantineAfterLogin = Duration(seconds: 25);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 12);
    if (pendingProductos >= 10) return const Duration(seconds: 18);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 700);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 80);

  /// Pump más espaciado: menos stack concurrente con listeners.
  static const Duration outboxPumpInterval = Duration(seconds: 50);

  /// Catálogo/precios: lento a propósito (no es lab de sync).
  static const Duration softPullInterval = Duration(seconds: 120);

  /// Soft-pull periódico ON, pero solo catálogo/config (nunca stock_ops).
  static const bool enablePeriodicSoftPull = true;

  /// Heal/purge cada N ticks del pump (1.4.38 era 3 → aún pesado).
  static const int healEveryNTicks = 8;

  /// Re-encolar docs recientes: raro (antes cada 2 ticks hinchaba outbox).
  static const int microCatchupEveryNTicks = 10;

  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Listeners ya cubren estas colecciones → soft-pull NO las vuelve a tirar.
  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 3);

  /// Solo catálogo / listas de precio / branding texto.
  /// stock_ops lo trae el pump dedicado — NO duplicar aquí.
  static const List<String> softPullOtherLanes = [
    'listas',
    'categorias',
    'permisos',
    'branding_text',
  ];

  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  /// Campo: maxApply ≥50 tumbaba el EXE. Techo duro **3**.
  static const int stockOpsHardCap = 3;

  static const int softPullProductosPageSize = 5;

  static const int softPullSkipIfPendingProductos = 15;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: stockOpsHardCap,
        recentLimit: 10,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 6,
        maxApply: 2,
        recentLimit: 8,
      );
    }
    return (
      maxPages: 1,
      pageSize: 6,
      maxApply: 2,
      recentLimit: 6,
    );
  }

  /// Soft-pull Windows: productos/precios + config rara.
  /// Nunca stock_ops (el pump unificado ya lo hace cada tick).
  /// Nunca remitos/ventas/clientes/compras (listeners).
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    final _ = prioritizeStockOps;
    // 3 de cada 4: catálogo; 1 de cada 4: config rotativa.
    if (n % 4 != 3) return 'productos_inc';
    final others = softPullOtherLanes;
    return others[(n ~/ 4) % others.length];
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 50);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 90);
    }
    return softPullInterval;
  }

  /// Negocio reciente: 0 en Windows (listeners alcanzan). Evita doble trabajo.
  static int recentBusinessDocsLimit({required int pendingProductos}) {
    final _ = pendingProductos;
    return 0;
  }

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
    return (
      negocioLimit: 5,
      clientesPage: 0,
      stockMaxPages: 1,
      stockPageSize: 10,
      stockMaxApply: stockOpsHardCap,
      stockRecentLimit: 12,
      stockRounds: 2,
      stockMicroBatch: 2,
      yieldMs: 220,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: pendingProductos < 30,
    );
  }

  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 8, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 1, pageSize: softPullProductosPageSize);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
