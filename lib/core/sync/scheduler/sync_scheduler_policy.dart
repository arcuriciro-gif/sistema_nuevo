import 'sync_priority.dart';

/// Capacidad de un tick por nivel (Sync Engine 2.0).
class SyncLevelClaims {
  const SyncLevelClaims({
    required this.l1,
    required this.l2,
    required this.l3,
    required this.l4,
    required this.turboActive,
    required this.mode,
  });

  final int l1;
  final int l2;
  final int l3;
  final int l4;
  final bool turboActive;

  /// focused | turbo | recovering
  final String mode;

  int get total => l1 + l2 + l3 + l4;
}

/// Plan legacy (2 carriles) — compat con callers viejos.
class SyncSchedulerPlan {
  const SyncSchedulerPlan({
    required this.criticalClaim,
    required this.backgroundClaim,
    required this.criticalTypes,
    required this.backgroundTypes,
    this.turboActive = false,
    this.levelClaims,
  });

  final int criticalClaim;
  final int backgroundClaim;
  final List<String> criticalTypes;
  final List<String> backgroundTypes;
  final bool turboActive;
  final SyncLevelClaims? levelClaims;
}

/// Política pura del scheduler (testeable sin Firebase).
class SyncSchedulerPolicy {
  SyncSchedulerPolicy._();

  static const level1Types = <String>[
    'venta',
    'remito',
    'stock_op',
    'compra',
    'cuenta_corriente',
    'cobranza',
    'pago_cc',
  ];

  static const level2Types = <String>[
    'cliente',
    'proveedor',
    'pedido',
    'pago',
  ];

  static const level3Types = <String>[
    'producto',
    'lista_precio',
  ];

  static const level4Types = <String>[
    'media',
    'branding',
    'import',
    'mantenimiento',
    'stats',
  ];

  /// Compat: L1+L2 = "crítico comercial".
  static const criticalEntityTypes = <String>[
    ...level1Types,
    ...level2Types,
  ];

  static const backgroundEntityTypes = <String>[
    ...level3Types,
    ...level4Types,
  ];

  static bool mustPreferCritical({
    required int pendingCritical,
    required int pendingBackground,
  }) {
    if (pendingCritical <= 0) return false;
    return true;
  }

  /// Modo Turbo: cola L1 vacía → máxima capacidad a L3/L4.
  /// Si aparece L1 → preemption: fondo casi a 0.
  static SyncLevelClaims planLevels({
    required int pendingL1,
    required int pendingL2,
    required int pendingL3,
    required int pendingL4,
    required bool isWindows,
    int adaptiveBatchL1 = 10,
    int adaptiveBatchBg = 20,
  }) {
    final l1Cap = isWindows ? adaptiveBatchL1.clamp(4, 12) : adaptiveBatchL1.clamp(8, 40);
    final l2Cap = isWindows ? 6 : 16;
    final l3Cap = isWindows ? adaptiveBatchBg.clamp(4, 24) : adaptiveBatchBg.clamp(8, 60);
    final l4Cap = isWindows ? 4 : 12;

    // --- Preemption L1 ---
    if (pendingL1 > 0) {
      return SyncLevelClaims(
        l1: pendingL1.clamp(1, l1Cap),
        l2: pendingL2 > 0 ? 1 : 0, // residual mínimo
        l3: 0,
        l4: 0,
        turboActive: false,
        mode: 'focused',
      );
    }

    // --- L2 alto: no turbo pleno ---
    if (pendingL2 > 0) {
      return SyncLevelClaims(
        l1: 0,
        l2: pendingL2.clamp(1, l2Cap),
        l3: pendingL3 > 0 ? (isWindows ? 1 : 2) : 0,
        l4: 0,
        turboActive: false,
        mode: 'focused',
      );
    }

    // --- TURBO: L1+L2 vacíos → toda la capacidad a fondo ---
    if (pendingL3 + pendingL4 > 0) {
      final turboL3 = pendingL3 <= 0 ? 0 : pendingL3.clamp(1, l3Cap);
      final turboL4 = pendingL4 <= 0
          ? 0
          : pendingL4.clamp(1, pendingL3 > 0 ? l4Cap : l3Cap);
      return SyncLevelClaims(
        l1: 0,
        l2: 0,
        l3: turboL3,
        l4: turboL4,
        turboActive: true,
        mode: 'turbo',
      );
    }

    return const SyncLevelClaims(
      l1: 0,
      l2: 0,
      l3: 0,
      l4: 0,
      turboActive: false,
      mode: 'idle',
    );
  }

  /// Compat 2-carriles + turbo.
  static SyncSchedulerPlan planTick({
    required int pendingCritical,
    required int pendingBackground,
    required bool isWindows,
    int pendingL1 = -1,
    int pendingL2 = -1,
    int pendingL3 = -1,
    int pendingL4 = -1,
    int adaptiveBatchL1 = 10,
    int adaptiveBatchBg = 20,
  }) {
    // Si no pasan desgloses L1–L4, aproximar desde critical/background.
    final l1 = pendingL1 >= 0 ? pendingL1 : pendingCritical;
    final l2 = pendingL2 >= 0 ? pendingL2 : 0;
    final l3 = pendingL3 >= 0 ? pendingL3 : pendingBackground;
    final l4 = pendingL4 >= 0 ? pendingL4 : 0;

    final levels = planLevels(
      pendingL1: l1,
      pendingL2: l2,
      pendingL3: l3,
      pendingL4: l4,
      isWindows: isWindows,
      adaptiveBatchL1: adaptiveBatchL1,
      adaptiveBatchBg: adaptiveBatchBg,
    );

    return SyncSchedulerPlan(
      criticalClaim: levels.l1 + levels.l2,
      backgroundClaim: levels.l3 + levels.l4,
      criticalTypes: criticalEntityTypes,
      backgroundTypes: backgroundEntityTypes,
      turboActive: levels.turboActive,
      levelClaims: levels,
    );
  }

  static bool shouldCoalesceUpsert({
    required String entityType,
    required String operation,
  }) =>
      SyncPriority.canCoalesce(entityType, operation);

  /// ¿Debe preemptar el lote de fondo? (apareció L1).
  static bool shouldPreemptBackground({required int pendingL1}) =>
      pendingL1 > 0;
}
