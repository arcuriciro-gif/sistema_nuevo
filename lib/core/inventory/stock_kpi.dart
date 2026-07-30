/// Criterio único de KPIs de stock (Inicio / Productos / Dashboard).
///
/// Campo: pantallas distintas usaban `== 0` vs `<= 0` → Sin stock 2881 vs 2871
/// (negativos solo contaban en una).
class StockKpi {
  StockKpi._();

  /// Tiene unidades disponibles para vender.
  static bool conStock(int stock) => stock > 0;

  /// Agotado o negativo (ambos son “sin stock” en la UI).
  static bool sinStock(int stock) => stock <= 0;

  /// Stock inválido / sobreventa.
  static bool negativo(int stock) => stock < 0;
}
