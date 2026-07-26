/// Política de sync en Windows desktop: estable, sin fantasma, ritmo razonable.
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Delay entre jobs normales del throttle (outbox/pull).
  static const Duration throttleDelayNormal = Duration(milliseconds: 500);

  /// Delay corto para acción de usuario (1 producto / listas).
  static const Duration throttleDelayInteractive = Duration(milliseconds: 80);

  /// Outbox pump: frecuente pero con micro-lotes (estable ≠ lento).
  static const Duration outboxPumpInterval = Duration(seconds: 45);

  /// Soft-pull: una colección por tick.
  static const Duration softPullInterval = Duration(seconds: 90);

  /// Reclaim inflight huérfanos tras crash (no demasiado agresivo).
  static const Duration reclaimStaleInflightAfter = Duration(minutes: 3);

  /// Lanes del soft-pull (no-productos).
  static const List<String> softPullOtherLanes = [
    'clientes',
    'ventas',
    'remitos',
    'stock_ops',
    'compras',
    'proveedores',
  ];

  /// ~33% productos, resto round-robin (menos presión Firebase que 50%).
  static String softPullLane(int n) {
    if (n % 3 == 0) {
      return (n ~/ 3) % 2 == 0 ? 'productos_inc' : 'productos_cat';
    }
    final otherIdx = ((n ~/ 3) * 2 + ((n % 3) - 1)) % softPullOtherLanes.length;
    return softPullOtherLanes[otherIdx];
  }

  /// En Windows el masivo (análisis de lista) solo encola outbox.
  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;
}
