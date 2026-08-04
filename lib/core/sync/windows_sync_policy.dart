/// Política de sync en Windows desktop — **automática simple (estilo 21 jul)**.
///
/// 1.4.47 — vuelve la sync en segundos que pediste probar:
/// - Listeners Firestore de negocio (ventas/remitos/clientes/compras) ON.
/// - Listener de productos ON (solo `docChanges` tras el snapshot inicial).
/// - Soft-pull + stock_ops inbound ON (techos anti-crash; no ráfagas de 60).
/// - Pump sube y baja (no solo salida).
/// - Sin depender del botón manual (como pediste el 21 jul).
///
/// Si el EXE se cae, avisá qué estabas haciendo y recortamos de a uno.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Tras login: breve pausa, luego listeners + pump.
  static const Duration quarantineAfterLogin = Duration(seconds: 18);

  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (pendingProductos >= 50) return const Duration(seconds: 10);
    if (pendingProductos >= 10) return const Duration(seconds: 14);
    return quarantineAfterLogin;
  }

  static const Duration throttleDelayNormal = Duration(milliseconds: 500);
  static const Duration throttleDelayInteractive = Duration(milliseconds: 50);

  /// Pump frecuente: subir cola + soft-pull.
  static const Duration outboxPumpInterval = Duration(seconds: 30);

  static const Duration softPullInterval = Duration(seconds: 25);
  static const bool enablePeriodicSoftPull = true;

  /// Sube y baja (como 21 jul). No solo-salida.
  static const bool outboundOnlyPump = false;

  /// Botón opcional: soft catch-up liviano (no es el camino principal).
  static const bool manualRefreshPushOnly = false;
  static const bool manualRefreshLocalOnly = false;

  static const int healEveryNTicks = 6;
  static const int microCatchupEveryNTicks = 4;

  /// Listeners de negocio ON — venta/remito en segundos.
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// También productos (docChanges). Diferencias de catálogo EXE↔APK.
  static const bool enableProductosListenerWindows = true;

  static const List<String> windowsBusinessListenerCollections = [
    'remitos',
    'ventas',
    'clientes',
    'compras',
  ];

  /// Respaldo si listeners fallan.
  static const int pollRemitosEveryNTicks = 3;
  static const int pollRemitosLimit = 20;

  /// Stock_ops inbound cada N ticks del pump.
  static const int stockOpsEveryNTicks = 2;

  /// Boot liviano (sin migración ledger masiva que tumba).
  static const bool skipHeavyBootMaintenance = true;

  /// Al arrancar: bajar productos para cerrar diferencias de catálogo.
  static const bool skipPrimerPullProductos = false;

  static const Duration reclaimStaleInflightAfter = Duration(minutes: 5);

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

  static const int softPullProductosPageSize = 25;

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

  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    if (prioritizeStockOps) {
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
      return const Duration(seconds: 15);
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
    return (
      negocioLimit: 15,
      clientesPage: 20,
      stockMaxPages: 1,
      stockPageSize: 12,
      stockMaxApply: stockOpsHardCap,
      stockRecentLimit: 20,
      stockRounds: 1,
      stockMicroBatch: 2,
      yieldMs: 200,
      schedulerTicks: 2,
      pullClientes: true,
      pullConfig: true,
      productosPageSize: 40,
      repararProyeccion: false,
      reconcilizarStockOps: false,
    );
  }

  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 12, maxApply: stockOpsHardCap);

  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 8, pageSize: 40);

  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
