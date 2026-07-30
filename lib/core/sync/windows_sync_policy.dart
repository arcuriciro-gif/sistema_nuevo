/// Política de sync en Windows desktop: cuarentena al login + sync eventual.
///
/// Prioridad #1: que el .exe no se caiga.
/// Prioridad #2: convergencia de stock + papelera + comprobantes.
/// Nunca subir hardCap ni reactivar listeners de productos (crash histórico).
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
  static const Duration throttleDelayInteractive = Duration(milliseconds: 50);

  /// Outbox pump (tras cuarentena): micro-lotes.
  /// 1.4.37: no bajar de 30s — stack heal+stock+soft cada 25s tumbaba EXE.
  static const Duration outboxPumpInterval = Duration(seconds: 30);

  /// Soft-pull mínimo entre corridas (el pump unificado debe respetarlo).
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

  /// Con cola de upload chica, priorizar convergencia de negocio + stock.
  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  /// @Deprecated — alias de [prioritizeBusinessConvergence].
  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  /// Presupuesto de pull stock_ops en Windows (ráfagas controladas).
  ///
  /// Campo: maxApply ≥50 tumbaba el EXE. Techo duro **4**.
  static const int stockOpsHardCap = 4;

  /// Página de productos en soft-pull Windows (anti-crash).
  static const int softPullProductosPageSize = 8;

  /// Si hay muchos pending de upload, no soft-pull (drenar primero).
  static const int softPullSkipIfPendingProductos = 30;

  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 10,
        maxApply: stockOpsHardCap,
        recentLimit: 16,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: 3,
        recentLimit: 12,
      );
    }
    return (
      maxPages: 1,
      pageSize: 8,
      maxApply: 2,
      recentLimit: 10,
    );
  }

  /// Soft-pull lane.
  ///
  /// Ciclo quieto de 6 (anti-crash): stock / productos / remitos /
  /// stock / ventas / productos → papelera converge sin ráfaga.
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    if (prioritizeStockOps) {
      switch (n % 6) {
        case 0:
          return 'stock_ops';
        case 1:
          return 'productos_inc';
        case 2:
          return 'remitos';
        case 3:
          return 'stock_ops';
        case 4:
          return 'ventas';
        default:
          return 'productos_inc';
      }
    }
    // Busy: stock_ops 1/3; productos 1/3; resto 1/3.
    if (n % 3 == 0) return 'stock_ops';
    if (n % 3 == 1) return 'productos_inc';
    final others = softPullOtherLanes
        .where((l) => l != 'stock_ops')
        .toList(growable: false);
    return others[(n ~/ 3) % others.length];
  }

  /// Intervalo del pump dedicado de stock_ops en Windows (anti-starvation).
  static const Duration windowsStockOpsPumpInterval = Duration(seconds: 30);

  /// Intervalo soft-pull cuando la outbox de productos está quieta.
  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 30);
    }
    return softPullInterval;
  }

  /// Cuántos docs recientes tirar por `actualizadoEn` (idempotente).
  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return 12;
    }
    return 0;
  }

  /// Presupuesto de "Actualizar ahora" en Windows.
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
    if (pendingProductos >= 50) {
      return (
        negocioLimit: 5,
        clientesPage: 0,
        stockMaxPages: 1,
        stockPageSize: 12,
        stockMaxApply: stockOpsHardCap,
        stockRecentLimit: 20,
        stockRounds: 4,
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
        stockMaxPages: 1,
        stockPageSize: 12,
        stockMaxApply: stockOpsHardCap,
        stockRecentLimit: 24,
        stockRounds: 4,
        stockMicroBatch: 2,
        yieldMs: 180,
        schedulerTicks: 1,
        pullClientes: false,
        pullConfig: true,
      );
    }
    return (
      negocioLimit: 8,
      clientesPage: 0,
      stockMaxPages: 1,
      stockPageSize: 12,
      stockMaxApply: stockOpsHardCap,
      stockRecentLimit: 24,
      stockRounds: 4,
      stockMicroBatch: 2,
      yieldMs: 160,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: true,
    );
  }

  /// Catch-up inicial Windows: suficiente para converger sin ráfaga letal.
  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 10, maxApply: stockOpsHardCap);

  /// Primer pull productos post-cuarentena (antes 2×25 tumbaba).
  static ({int maxPages, int pageSize}) windowsPrimerPullProductos() =>
      (maxPages: 1, pageSize: softPullProductosPageSize);

  /// En Windows el masivo (análisis de lista) solo encola outbox.
  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Storage / chat remoto / branding snapshot: off en Windows.
  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
