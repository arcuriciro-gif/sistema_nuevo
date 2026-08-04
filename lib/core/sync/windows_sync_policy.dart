/// Política de sync en Windows desktop: EXE no se cae.
///
/// Prioridad #1 absoluta: que el .exe no se caiga.
///
/// 1.4.42 — modo **solo salida** en background.
/// 1.4.45 — «Actualizar ahora» push-only (como 1.4.20).
/// 1.4.46 — botón PC **solo local**: limpia fantasmas en SQLite; cero Firebase.
///   El drain real lo hace el pump cada ~120s. El botón no debe tumbar el EXE.
/// - Sin listeners, soft-pull, heal, micro-catchup, poll remitos, stock_ops
///   periódico ni migración ledger pesada al boot.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: no tocar Firebase de colección.
  static const Duration quarantineAfterLogin = Duration(seconds: 35);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 20);
    if (pendingProductos >= 10) return const Duration(seconds: 28);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 1000);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 150);

  /// Pump solo para subir cola local.
  static const Duration outboxPumpInterval = Duration(seconds: 120);

  static const Duration softPullInterval = Duration(seconds: 600);
  static const bool enablePeriodicSoftPull = false;

  /// Solo salida: no traer del cloud en el pump.
  static const bool outboundOnlyPump = true;

  /// «Actualizar ahora» en Windows: sin pull inbound.
  /// Aprendizaje de campo 1.4.20 — reconfirmado 1.4.45.
  static const bool manualRefreshPushOnly = true;

  /// 1.4.46 — el botón NO escribe a Firebase (ni drain).
  /// Solo limpia pendientes fantasma locales. Campo: drain en el botón
  /// también tumbaba el EXE; el pump background se encarga de subir.
  static const bool manualRefreshLocalOnly = true;

  static const int healEveryNTicks = 0;
  static const int microCatchupEveryNTicks = 0;

  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      false;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  /// Poll remitos OFF (inbound solo manual).
  static const int pollRemitosEveryNTicks = 0;
  static const int pollRemitosLimit = 0;

  /// Stock_ops inbound OFF en pump.
  static const int stockOpsEveryNTicks = 0;

  /// Boot: no migración ledger masiva / recover cloud.
  static const bool skipHeavyBootMaintenance = true;

  /// Boot: no pull de productos automático.
  static const bool skipPrimerPullProductos = true;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 8);

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

  static const int stockOpsHardCap = 1;

  static const int softPullProductosPageSize = 4;

  static const int softPullSkipIfPendingProductos = 10;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    final _ = pendingProductos;
    return (
      maxPages: 1,
      pageSize: 4,
      maxApply: stockOpsHardCap,
      recentLimit: 0,
    );
  }

  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    final _ = prioritizeStockOps;
    if (n % 4 != 3) return 'productos_inc';
    final others = softPullOtherLanes;
    return others[(n ~/ 4) % others.length];
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 120);

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
    int productosPageSize,
    bool repararProyeccion,
    bool reconcilizarStockOps,
  }) manualRefreshBudgetWindows({required int pendingProductos}) {
    final _ = pendingProductos;
    // 1.4.44: micro absoluto — el refresh manual tumbaba el EXE.
    return (
      negocioLimit: 2,
      clientesPage: 0,
      stockMaxPages: 1,
      stockPageSize: 3,
      stockMaxApply: 1,
      stockRecentLimit: 3,
      stockRounds: 1,
      stockMicroBatch: 1,
      yieldMs: 400,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: false,
      productosPageSize: 2,
      repararProyeccion: false,
      reconcilizarStockOps: false,
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
