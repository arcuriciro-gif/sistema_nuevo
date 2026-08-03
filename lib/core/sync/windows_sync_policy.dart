/// Política de sync en Windows desktop: supervivencia del EXE.
///
/// Prioridad #1: que el .exe no se caiga.
/// Prioridad #2: lo del local (productos/precios, comprobantes, stock).
///
/// 1.4.41: corte duro del trabajo en background que tumba la PC —
/// sin soft-pull, sin micro-catchup, sin heal periódico, sin listeners
/// de Firestore. El pump solo drena outbox + stock_ops mínimo + poll
/// liviano de comprobantes. Catálogo/precios: login + "Actualizar ahora".
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: solo absorber outbox local; sin Firebase de colección.
  static const Duration quarantineAfterLogin = Duration(seconds: 30);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 15);
    if (pendingProductos >= 10) return const Duration(seconds: 22);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 900);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 120);

  /// Pump espaciado: menos stack concurrente.
  static const Duration outboxPumpInterval = Duration(seconds: 90);

  /// Soft-pull OFF en Windows (1.4.41). Catálogo vía primer pull + manual.
  static const Duration softPullInterval = Duration(seconds: 300);
  static const bool enablePeriodicSoftPull = false;

  /// Heal/purge OFF en background (0 = nunca en pump).
  static const int healEveryNTicks = 0;

  /// Micro-catchup OFF (re-encolar docs hincha outbox y tumba EXE).
  static const int microCatchupEveryNTicks = 0;

  /// Listeners Firestore OFF — snapshots concurrentes tumbaron el EXE.
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      false;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  /// Poll liviano de comprobantes cuando no hay listeners.
  static const int pollRemitosEveryNTicks = 2;
  static const int pollRemitosLimit = 4;

  /// Stock_ops no en cada tick.
  static const int stockOpsEveryNTicks = 2;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 5);

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

  /// Techo duro **1** (antes 3 seguía cayendo en campo).
  static const int stockOpsHardCap = 1;

  static const int softPullProductosPageSize = 4;

  static const int softPullSkipIfPendingProductos = 10;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    // recentLimit 0: no doble pull (remoto + recientes) en el mismo tick.
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 4,
        maxApply: stockOpsHardCap,
        recentLimit: 0,
      );
    }
    return (
      maxPages: 1,
      pageSize: 4,
      maxApply: stockOpsHardCap,
      recentLimit: 0,
    );
  }

  /// Soft-pull (si se reactivara): solo catálogo, nunca stock_ops/negocio.
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    final _ = prioritizeStockOps;
    if (n % 4 != 3) return 'productos_inc';
    final others = softPullOtherLanes;
    return others[(n ~/ 4) % others.length];
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 90);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    final _ = pendingProductos;
    return softPullInterval;
  }

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
      negocioLimit: 4,
      clientesPage: 0,
      stockMaxPages: 1,
      stockPageSize: 6,
      stockMaxApply: stockOpsHardCap,
      stockRecentLimit: 6,
      stockRounds: 1,
      stockMicroBatch: 1,
      yieldMs: 280,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: pendingProductos < 20,
    );
  }

  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 4, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 1, pageSize: softPullProductosPageSize);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
