/// Criterio único de KPIs de stock (Inicio / Productos / Dashboard / APK).
///
/// Campo 2026-07-28: Inicio usaba `stock <= 0` y Productos `stock == 0`,
/// entonces el mismo EXE mostraba Sin stock 2881 vs 2871 (los 10 negativos
/// solo contaban en Inicio).
class StockKpi {
  StockKpi._();

  /// Tiene unidades disponibles para vender.
  static bool conStock(int stock) => stock > 0;

  /// Agotado o negativo (ambos son “sin stock” en la UI).
  static bool sinStock(int stock) => stock <= 0;

  /// Stock inválido / sobreventa.
  static bool negativo(int stock) => stock < 0;
}
