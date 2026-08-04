/// Política de sync en Windows desktop — automática, sin tumbar el EXE.
///
/// 1.4.48 — ajuste de campo tras 1.4.47:
/// - Botón «Actualizar ahora» = SOLO limpia fantasmas locales (cero Firebase).
///   El botón con pull/drain volvió a tumbar el EXE.
/// - Listeners de negocio ON (ventas/remitos/clientes/compras) → segundos.
/// - Listener de productos OFF (snapshot 10k tumbaba / divergía).
/// - Productos convergen por soft-pull: incremental + barrido catálogo.
/// - Soft-pull / stock_ops / primer pull ON, con techos anti-crash.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: breve pausa, luego listeners negocio + pump.
  static const Duration quarantineAfterLogin = Duration(seconds: 18);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 10);
    if (pendingProductos >= 10) return const Duration(seconds: 14);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 500);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 50);

  /// Pump frecuente: subir cola + soft-pull productos/negocio.
  static const Duration outboxPumpInterval = Duration(seconds: 25);

  static const Duration softPullInterval = Duration(seconds: 18);
  static const bool enablePeriodicSoftPull = true;

  /// Sube y baja. No solo-salida.
  static const bool outboundOnlyPump = false;

  /// Botón: NUNCA Firebase. Aprendizaje de campo (cae el EXE).
  static const bool manualRefreshPushOnly = true;
  static const bool manualRefreshLocalOnly = true;

  static const int healEveryNTicks = 6;
  static const int microCatchupEveryNTicks = 4;

  /// Listeners de negocio ON — venta/remito en segundos.
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Productos: NO listener (10k snapshot tumba / deja half-apply).
  /// Convergen por soft-pull productos_inc + productos_cat.
  static const bool enableProductosListenerWindows = false;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  static const int pollRemitosEveryNTicks = 3;
  static const int pollRemitosLimit = 20;

  static const int stockOpsEveryNTicks = 2;

  static const bool skipHeavyBootMaintenance = true;

  /// Al arrancar: bajar productos para cerrar diferencias de catálogo.
  static const bool skipPrimerPullProductos = false;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 5);

  /// Reiniciar barrido catálogo si el último complete es más viejo que esto.
  static const Duration catalogSweepRestartAfter = Duration(minutes: 8);

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

  /// Techo duro anti-crash (aprendizaje 1.4.20: 60 tumbaba).
  static const int stockOpsHardCap = 4;

  static const int softPullProductosPageSize = 30;

  static const int softPullSkipIfPendingProductos = 80;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 12,
        maxApply: stockOpsHardCap,
        recentLimit: 20,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: 2,
        recentLimit: 0,
      );
    }
    return (
      maxPages: 1,
      pageSize: 4,
      maxApply: 1,
      recentLimit: 0,
    );
  }

  /// Siempre incluye productos_inc y productos_cat (cierra diferencias de lista).
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    if (prioritizeStockOps) {
      switch (n % 8) {
        case 0:
          return 'remitos';
        case 1:
          return 'ventas';
        case 2:
          return 'productos_inc';
        case 3:
          return 'stock_ops';
        case 4:
          return 'productos_cat';
        case 5:
          return 'compras';
        case 6:
          return 'productos_inc';
        default:
          return 'clientes';
      }
    }
    if (n % 3 == 0) {
      return (n ~/ 3) % 2 == 0 ? 'productos_inc' : 'productos_cat';
    }
    final otherIdx =
        ((n ~/ 3) * 2 + ((n % 3) - 1)) % softPullOtherLanes.length;
    return softPullOtherLanes[otherIdx];
  }

  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 45);

  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 12);
    }
    return softPullInterval;
  }

  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (pendingProductos <= 5) return 25;
    if (pendingProductos <= 30) return 12;
    return 6;
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
    // El botón ya no usa este budget (local-only). Queda por tests/legado.
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
          (maxPages: 1, pageSize: 12, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 6, pageSize: 40);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
