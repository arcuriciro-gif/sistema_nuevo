/// Sync Windows — comercio chico, automática, sin tumbar el EXE.
///
/// 1.4.51 — el EXE seguía cayendo con sync agresiva:
/// - Sin listener de productos (solo soft-pull lento).
/// - Listeners de negocio ON (ventas/comprobantes) con pump espaciado.
/// - Papelera: reconcile acotado (pocos gets).
/// - Sin botón manual.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  static const Duration quarantineAfterLogin = Duration(seconds: 28);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 16);
    if (pendingProductos >= 10) return const Duration(seconds: 22);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 700);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 80);

  static const Duration outboxPumpInterval = Duration(seconds: 55);

  static const Duration softPullInterval = Duration(seconds: 40);
  static const bool enablePeriodicSoftPull = true;

  static const bool outboundOnlyPump = false;

  static const bool manualRefreshPushOnly = true;
  static const bool manualRefreshLocalOnly = true;

  static const int healEveryNTicks = 10;
  static const int microCatchupEveryNTicks = 5;

  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// OFF: el listener de productos seguía contribuyendo a caídas.
  static const bool enableProductosListenerWindows = false;
  static const bool skipProductosInitialSnapshotApply = true;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  static const int pollRemitosEveryNTicks = 4;
  static const int pollRemitosLimit = 15;

  static const int stockOpsEveryNTicks = 3;

  static const bool skipHeavyBootMaintenance = true;
  static const bool skipPrimerPullProductos = false;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 6);
  static const Duration catalogSweepRestartAfter = Duration(minutes: 12);

  /// Máx. productos de papelera a consultar por pasada (anti-crash).
  static const int papeleraReconcileLimit = 25;

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

  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  static const int stockOpsHardCap = 2;
  static const int softPullProductosPageSize = 25;
  static const int softPullSkipIfPendingProductos = 60;

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
    return (
      maxPages: 1,
      pageSize: 4,
      maxApply: 1,
      recentLimit: 0,
    );
  }

  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    switch (n % 6) {
      case 0:
        return 'productos_inc';
      case 1:
        return prioritizeStockOps ? 'remitos' : 'productos_cat';
      case 2:
        return 'ventas';
      case 3:
        return 'productos_cat';
      case 4:
        return 'stock_ops';
      default:
        return softPullOtherLanes[(n ~/ 6) % softPullOtherLanes.length];
    }
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 60);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 25);
    }
    return softPullInterval;
  }

  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (pendingProductos <= 5) return 15;
    if (pendingProductos <= 30) return 8;
    return 4;
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
    int productosPageSize,
    bool repararProyeccion,
    bool reconcilizarStockOps,
  }) manualRefreshBudgetWindows({required int pendingProductos}) {
    final _ = pendingProductos;
    return (
      negocioLimit: 0,
      clientesPage: 0,
      stockMaxPages: 0,
      stockPageSize: 0,
      stockMaxApply: 0,
      stockRecentLimit: 0,
      stockRounds: 0,
      stockMicroBatch: 0,
      yieldMs: 0,
      schedulerTicks: 0,
      pullClientes: false,
      pullConfig: false,
      productosPageSize: 0,
      repararProyeccion: false,
      reconcilizarStockOps: false,
    );
  }

  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 8, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 3, pageSize: 30);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
