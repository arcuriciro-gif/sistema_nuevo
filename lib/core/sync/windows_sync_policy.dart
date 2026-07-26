/// Política de sync en Windows desktop: rápido en lo interactivo,
/// gradual en lo masivo (protege el .exe).
class WindowsSyncPolicy {
  WindowsSyncPolicy._();

  /// Delay entre jobs normales del throttle (outbox/pull).
  static const Duration throttleDelayNormal = Duration(milliseconds: 800);

  /// Delay corto para acción de usuario (1 producto / listas).
  static const Duration throttleDelayInteractive = Duration(milliseconds: 120);

  /// Lanes del soft-pull: productos ~50% de los ticks; el resto round-robin.
  static const List<String> softPullOtherLanes = [
    'clientes',
    'ventas',
    'remitos',
    'stock_ops',
    'compras',
    'proveedores',
  ];

  /// Devuelve el lane a ejecutar para el tick [n] (0-based).
  static String softPullLane(int n) {
    if (n % 2 == 0) {
      return (n ~/ 2) % 2 == 0 ? 'productos_inc' : 'productos_cat';
    }
    return softPullOtherLanes[(n ~/ 2) % softPullOtherLanes.length];
  }

  /// En Windows el masivo (análisis de lista) solo encola outbox.
  static bool bulkSoloEncolar({required bool isWindowsDesktop}) =>
      isWindowsDesktop;
}
