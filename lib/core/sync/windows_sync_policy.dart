/// Sync Windows — comercio chico, automática simple (estilo 21 jul).
///
/// 1.4.49:
/// - Sin botón manual (tumbaba el EXE).
/// - Listeners de negocio + productos (solo cambios, no snapshot 10k).
/// - Soft-pull de catálogo para alinear listas / papelera / sin stock.
/// - Fotos: URLs desde el celular; PC no sube Storage (estabilidad).
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  static const Duration quarantineAfterLogin = Duration(seconds: 12);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 8);
    if (pendingProductos >= 10) return const Duration(seconds: 10);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 400);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 40);

  static const Duration outboxPumpInterval = Duration(seconds: 20);

  static const Duration softPullInterval = Duration(seconds: 12);
  static const bool enablePeriodicSoftPull = true;

  /// Sube y baja. Sync automática completa.
  static const bool outboundOnlyPump = false;

  /// Botón removido de la UI; flags por si queda algún caller.
  static const bool manualRefreshPushOnly = true;
  static const bool manualRefreshLocalOnly = true;

  static const int healEveryNTicks = 8;
  static const int microCatchupEveryNTicks = 3;

  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Listener productos ON, pero solo `docChanges` (sin apply del snapshot 10k).
  static const bool enableProductosListenerWindows = true;

  /// No aplicar el snapshot inicial completo (tumbaba / half-apply).
  static const bool skipProductosInitialSnapshotApply = true;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  static const int pollRemitosEveryNTicks = 2;
  static const int pollRemitosLimit = 25;

  static const int stockOpsEveryNTicks = 1;

  static const bool skipHeavyBootMaintenance = true;
  static const bool skipPrimerPullProductos = false;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 5);
  static const Duration catalogSweepRestartAfter = Duration(minutes: 5);

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
      pendingProductos <= 8;

  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  static const int stockOpsHardCap = 4;
  static const int softPullProductosPageSize = 40;
  static const int softPullSkipIfPendingProductos = 100;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 15,
        maxApply: stockOpsHardCap,
        recentLimit: 30,
      );
    }
    return (
      maxPages: 1,
      pageSize: 8,
      maxApply: 2,
      recentLimit: 0,
    );
  }

  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    // Comercio chico: mitad del tiempo productos (lista / papelera / precios).
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

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 30);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 8);
    }
    return softPullInterval;
  }

  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (pendingProductos <= 8) return 30;
    if (pendingProductos <= 40) return 15;
    return 8;
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
          (maxPages: 1, pageSize: 15, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 10, pageSize: 50);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
