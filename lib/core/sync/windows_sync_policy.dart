/// Política de sync en Windows desktop: cuarentena al login + sync eventual.
///
/// Prioridad #1: que el .exe no se caiga.
/// Prioridad #2: convergencia de stock + papelera + comprobantes.
/// Nunca subir hardCap ni reactivar listeners de productos (crash histórico).
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

  /// 1.4.38: 40s — menos stack concurrente con listeners de negocio.
  static const Duration outboxPumpInterval = Duration(seconds: 40);

  static const Duration softPullInterval = Duration(seconds: 75);

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

  /// Solo lo que NO tiene listener (productos/stock/config).
  static const List<String> softPullOtherLanes = [
    'stock_ops',
    'proveedores',
    'listas',
    'categorias',
    'permisos',
    'branding_text',
  ];

  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  /// Campo: maxApply ≥50 tumbaba el EXE. Techo duro **3** (1.4.38).
  static const int stockOpsHardCap = 3;

  static const int softPullProductosPageSize = 6;

  static const int softPullSkipIfPendingProductos = 20;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: stockOpsHardCap,
        recentLimit: 12,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 6,
        maxApply: 2,
        recentLimit: 10,
      );
    }
    return (
      maxPages: 1,
      pageSize: 6,
      maxApply: 2,
      recentLimit: 8,
    );
  }

  /// Soft-pull Windows: NUNCA remitos/ventas/clientes/compras (ya hay listener).
  /// Ciclo: stock / productos / stock / config.
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    final _ = prioritizeStockOps;
    switch (n % 4) {
      case 0:
        return 'stock_ops';
      case 1:
        return 'productos_inc';
      case 2:
        return 'stock_ops';
      default:
        final others = softPullOtherLanes
            .where((l) => l != 'stock_ops')
            .toList(growable: false);
        return others[(n ~/ 4) % others.length];
    }
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 40);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 45);
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
      stockRecentLimit: 16,
      stockRounds: 3,
      stockMicroBatch: 2,
      yieldMs: 200,
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
