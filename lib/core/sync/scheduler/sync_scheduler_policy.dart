import 'sync_priority.dart';

/// Plan de un tick del scheduler: siempre crítico antes que fondo.
class SyncSchedulerPlan {
  const SyncSchedulerPlan({
    required this.criticalClaim,
    required this.backgroundClaim,
    required this.criticalTypes,
    required this.backgroundTypes,
  });

  final int criticalClaim;
  final int backgroundClaim;
  final List<String> criticalTypes;
  final List<String> backgroundTypes;
}

/// Política pura del scheduler (testeable sin Firebase).
class SyncSchedulerPolicy {
  SyncSchedulerPolicy._();

  static const criticalEntityTypes = <String>[
    'venta',
    'remito',
    'stock_op',
    'compra',
    'cliente',
    'proveedor',
  ];

  static const backgroundEntityTypes = <String>[
    'producto',
    'media',
    'branding',
    'import',
  ];

  /// ¿Hay backlog crítico que debe drenarse YA (ignorar fondo)?
  static bool mustPreferCritical({
    required int pendingCritical,
    required int pendingBackground,
  }) {
    if (pendingCritical <= 0) return false;
    // Si hay cualquier crítico, el fondo no monopoliza el tick.
    return true;
  }

  /// Capacidad de claim por tick. Crítico siempre tiene cupo propio.
  static SyncSchedulerPlan planTick({
    required int pendingCritical,
    required int pendingBackground,
    required bool isWindows,
  }) {
    final critCap = isWindows ? 10 : 40;
    final bgCap = isWindows ? 4 : 20;

    final criticalClaim =
        pendingCritical <= 0 ? 0 : pendingCritical.clamp(1, critCap);

    // Fondo solo si no hay críticos, o cupo residual muy chico.
    var backgroundClaim = 0;
    if (pendingBackground > 0) {
      if (pendingCritical == 0) {
        backgroundClaim = pendingBackground.clamp(1, bgCap);
      } else if (pendingCritical < critCap ~/ 2) {
        // Hay críticos pero pocos: 1–2 de fondo máximo (no bloquear UI).
        backgroundClaim = isWindows ? 1 : 2;
      }
    }

    return SyncSchedulerPlan(
      criticalClaim: criticalClaim,
      backgroundClaim: backgroundClaim,
      criticalTypes: criticalEntityTypes,
      backgroundTypes: backgroundEntityTypes,
    );
  }

  /// Coalesce seguro: mismo producto, solo metadata/precio — no stock_op.
  static bool shouldCoalesceUpsert({
    required String entityType,
    required String operation,
  }) =>
      SyncPriority.canCoalesce(entityType, operation);
}
