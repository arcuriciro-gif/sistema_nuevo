/// Política de sync en Windows desktop: cuarentena al login + sync eventual.
///
/// Prioridad: que el .exe no se caiga. La sync converge después, sin ráfagas.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Campo 2026-07-28: el EXE se cerraba solo ~2 min después del login
  /// (listeners de negocio + soft-pull + primer drain post-cuarentena).
  /// Con esto en true: solo outbox chico; sin snapshots Firestore ni soft-pull.
  /// Actualizar ahora = PUSH + micro-rondas de stock_ops (maxApply≤2).
  static const bool freezeBackgroundForStability = true;

  /// Tras login: solo absorber outbox local; sin Firebase de colección.
  static const Duration quarantineAfterLogin = Duration(seconds: 20);

  /// Si hay mucha cola de productos, acortar cuarentena (no dejar
  /// "arranque 45s" con 500 pending y 0 intentos).
  static Duration quarantineForBacklog({required int pendingProductos}) {
    if (freezeBackgroundForStability) {
      return const Duration(seconds: 8);
    }
    if (pendingProductos >= 50) return const Duration(seconds: 10);
    if (pendingProductos >= 10) return const Duration(seconds: 15);
    return quarantineAfterLogin;
  }

  /// Delay entre jobs normales del throttle (outbox/pull).
  static const Duration throttleDelayNormal = Duration(milliseconds: 600);

  /// Delay corto para acción de usuario (1 producto / remito / cliente).
  /// Objetivo: reflejar en el otro dispositivo en segundos, no minutos.
  static const Duration throttleDelayInteractive = Duration(milliseconds: 50);

  /// Outbox pump (tras cuarentena): micro-lotes más frecuentes.
  static Duration get outboxPumpInterval => freezeBackgroundForStability
      ? const Duration(seconds: 45)
      : const Duration(seconds: 25);

  /// Soft-pull: convergencia catálogo/stock (no sustituye listeners de negocio).
  static const Duration softPullInterval = Duration(seconds: 60);

  /// Listeners Firestore en Windows SOLO para colecciones chicas de negocio.
  /// Productos/branding/Storage siguen OFF (eran los que tumbaban el .exe).
  /// Congelado: OFF — el snapshot inicial de remitos/ventas tumbaba a los ~2 min.
  static bool enableBusinessDocListeners({required bool isWindowsDesktop}) =>
      isWindowsDesktop && !freezeBackgroundForStability;

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

  /// Con cola de upload chica, priorizar convergencia de negocio + stock
  /// (remitos/ventas/stock_ops). Campo: venta rápida EXE↔APK no cruzaba.
  static bool prioritizeBusinessConvergence({required int pendingProductos}) =>
      pendingProductos <= 5;

  /// @Deprecated — alias de [prioritizeBusinessConvergence].
  static bool prioritizeStockOpsPull({required int pendingProductos}) =>
      prioritizeBusinessConvergence(pendingProductos: pendingProductos);

  /// Presupuesto de pull stock_ops en Windows (ráfagas controladas).
  ///
  /// Campo 1.4.20: con ≤5 productos pending (caso real del usuario) el
  /// presupuesto "quieto" llegaba a maxApply **60** y tumbaba el .exe
  /// en soft-pull / post-Actualizar ahora. Techo duro: **4**.
  static ({int maxPages, int pageSize, int maxApply, int recentLimit})
      stockOpsPullBudget({required int pendingProductos}) {
    // Techo anti-crash absoluto (documentado: ≥50 tumba EXE).
    const hardCap = 4;
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return (
        maxPages: 1,
        pageSize: 10,
        maxApply: hardCap,
        recentLimit: 20,
      );
    }
    if (pendingProductos <= 50) {
      return (
        maxPages: 1,
        pageSize: 8,
        maxApply: 3,
        recentLimit: 15,
      );
    }
    return (
      maxPages: 1,
      pageSize: 8,
      maxApply: 2,
      recentLimit: 12,
    );
  }

  /// Soft-pull lane.
  ///
  /// Con [prioritizeStockOps]/convergencia de negocio):
  ///   remitos / ventas / stock_ops / compras en rotación densa.
  /// Sin eso: ~33% productos, resto round-robin.
  static String softPullLane(int n, {bool prioritizeStockOps = false}) {
    if (prioritizeStockOps) {
      // Ciclo de 6: negocio primero (campo venta rápida EXE↔APK).
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
          return 'stock_ops';
        default:
          return (n ~/ 6).isEven ? 'productos_inc' : 'clientes';
      }
    }
    if (n % 3 == 0) {
      return (n ~/ 3) % 2 == 0 ? 'productos_inc' : 'productos_cat';
    }
    final otherIdx =
        ((n ~/ 3) * 2 + ((n % 3) - 1)) % softPullOtherLanes.length;
    return softPullOtherLanes[otherIdx];
  }

  /// Intervalo soft-pull más corto cuando ya no hay cola de productos.
  static Duration softPullIntervalFor({required int pendingProductos}) {
    if (freezeBackgroundForStability) {
      // Soft-pull OFF de facto (pump no se arranca); valor por si alguien llama.
      return const Duration(hours: 24);
    }
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return const Duration(seconds: 20);
    }
    return softPullInterval;
  }

  /// Cuántos docs recientes tirar por `actualizadoEn` (idempotente).
  static int recentBusinessDocsLimit({required int pendingProductos}) {
    if (prioritizeBusinessConvergence(pendingProductos: pendingProductos)) {
      return 25;
    }
    return 0;
  }

  /// Presupuesto de "Actualizar ahora" en Windows.
  ///
  /// Con `freezeBackgroundForStability` el soft-pull/listeners están OFF:
  /// este gesto es el **único** canal de bajada de stock_ops al PC.
  /// Micro-rondas de maxApply≤2 + yield (techo total ≤40 < crash ≥50).
  /// Sin config, sin negocio, sin reactivar soft-pull.
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
    bool pullStockOnManual,
  }) manualRefreshBudgetWindows({required int pendingProductos}) {
    // Push + N micro-rondas (≤2 ops c/u). Total ≤40 aplica/gesto.
    // pendingProductos no agranda el pull (anti-crash); solo el push drena.
    return (
      negocioLimit: 0,
      clientesPage: 0,
      stockMaxPages: 1,
      stockPageSize: 8,
      stockMaxApply: 2,
      stockRecentLimit: 8,
      stockRounds: 20, // 20×2=40 < umbral crash histórico ≥50
      stockMicroBatch: 1,
      yieldMs: 200,
      schedulerTicks: 1,
      pullClientes: false,
      pullConfig: false,
      pullStockOnManual: true,
    );
  }

  /// Catch-up inicial Windows: suficiente para converger sin ráfaga letal.
  static ({int maxPages, int pageSize, int maxApply})
      windowsCatchupStockOpsBudget() =>
          (maxPages: 1, pageSize: 10, maxApply: 4);

  /// Plan de drain del outbox Windows (scheduler v2).
  ///
  /// **Crítico primero:** ventas/remitos/stock/clientes nunca esperan detrás
  /// de miles de productos de importación. El fondo (productos) solo corre
  /// con cupo residual o cuando no hay críticos.
  static List<({List<String> types, int claim})> outboxDrainPlan({
    required Map<String, int> breakdown,
    required int tick,
  }) {
    final nCritDocs = (breakdown['venta'] ?? 0) +
        (breakdown['remito'] ?? 0) +
        (breakdown['compra'] ?? 0) +
        (breakdown['cliente'] ?? 0) +
        (breakdown['proveedor'] ?? 0);
    final nStock = breakdown['stock_op'] ?? 0;
    final nProd = breakdown['producto'] ?? 0;
    final plan = <({List<String> types, int claim})>[];

    if (nCritDocs > 0) {
      plan.add((
        types: const ['venta', 'remito', 'compra', 'cliente', 'proveedor'],
        claim: nCritDocs.clamp(1, 10),
      ));
    }
    if (nStock > 0) {
      plan.add((
        types: const ['stock_op'],
        claim: nStock.clamp(1, 8),
      ));
    }
    // Fondo: solo si no hay críticos, o cupo mínimo residual.
    if (nProd > 0) {
      final bgClaim = (nCritDocs + nStock) == 0
          ? nProd.clamp(1, 6)
          : 1;
      plan.add((
        types: const ['producto'],
        claim: bgClaim,
      ));
    }
    // tick se conserva por compat API / métricas de rotación.
    if (plan.isEmpty && tick >= 0) {
      return plan;
    }
    return plan;
  }

  /// En Windows el masivo (análisis de lista) solo encola outbox.
  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;

  /// Storage / chat remoto / branding snapshot: off en Windows.
  static bool disableRemoteMediaAndChatListeners({
    required bool isWindowsDesktop,
  }) =>
      isWindowsDesktop;
}
