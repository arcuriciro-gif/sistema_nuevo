/// Sync Windows — comercio chico, automática, sin tumbar el EXE.
///
/// 1.4.52 — el EXE seguía cayendo en 1.4.51:
/// - Sin listeners de productos NI de negocio (solo soft-pull + poll).
/// - Soft-pull más lento; stock_ops con hardCap chico pero más frecuente
///   cuando la cola de productos está vacía (cierra “sin stock” EXE↔APK).
/// - Papelera: reconcile acotado.
/// - Sin botón manual de sync en la UI diaria.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  static const Duration quarantineAfterLogin = Duration(seconds: 40);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 22);
    if (pendingProductos >= 10) return const Duration(seconds: 30);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 900);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 120);

  static const Duration outboxPumpInterval = Duration(seconds: 70);

  static const Duration softPullInterval = Duration(seconds: 55);
  static const bool enablePeriodicSoftPull = true;

  static const bool outboundOnlyPump = false;

  static const bool manualRefreshPushOnly = true;
  static const bool manualRefreshLocalOnly = true;

  static const int healEveryNTicks = 12;
  static const int microCatchupEveryNTicks = 6;

  /// OFF: los snapshots de negocio también contribuían a caídas del EXE.
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      false;

  /// OFF: el listener de productos seguía contribuyendo a caídas.
  static const bool enableProductosListenerWindows = false;
  static const bool skipProductosInitialSnapshotApply = true;

  static const List<String> windowsBusinessListenerCollections = <String>[
    // vacío a propósito — poll vía soft-pull / unified pump
  ];

  static const int pollRemitosEveryNTicks = 3;
  static const int pollRemitosLimit = 12;

  /// Más frecuente que el soft-pull: cierra divergencia de “sin stock”.
  static const int stockOpsEveryNTicks = 2;

  static const bool skipHeavyBootMaintenance = true;
  static const bool skipPrimerPullProductos = false;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 8);
  static const Duration catalogSweepRestartAfter = Duration(minutes: 15);

  /// Máx. productos de papelera a consultar por pasada (anti-crash).
  static const int papeleraReconcileLimit = 18;

  static const List<String> softPullOtherLanes = [
    'clientes',
    'ventas',
    'remitos',
    'papelera',
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
  /// Cuando no hay cola de productos, un poco más de apply para cerrar
  /// el KPI “sin stock” (campo: APK 2879 / EXE 2878).
  static const int stockOpsHardCapIdle = 3;
  static const int softPullProductosPageSize = 20;
  static const int softPullSkipIfPendingProductos = 60;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 10,
        maxApply: stockOpsHardCapIdle,
        recentLimit: 16,
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
        return prioritizeStockOps ? 'papelera' : 'papelera';
      default:
        return softPullOtherLanes[(n ~/ 6) % softPullOtherLanes.length];
    }
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 75);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 35);
    }
    return softPullInterval;
  }

  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (pendingProductos <= 5) return 12;
    if (pendingProductos <= 30) return 6;
    return 3;
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
          (maxPages: 1, pageSize: 10, maxApply: stockOpsHardCapIdle);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 2, pageSize: 25);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
