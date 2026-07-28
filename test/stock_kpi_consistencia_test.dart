import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/inventory/stock_kpi.dart';

/// Campo: mismo EXE Inicio Sin stock 2881 vs Productos 2871.
void main() {
  test('Inicio y Productos deben usar el mismo criterio (<=0)', () {
    const total = 2884;
    const conStock = 3;
    const negativos = 10; // ej. ABROJO 16mm stock -1
    const cero = total - conStock - negativos; // 2871

    final sinStockUnificado = List.generate(total, (i) {
      if (i < conStock) return 5;
      if (i < conStock + negativos) return -1;
      return 0;
    }).where(StockKpi.sinStock).length;

    expect(cero, 2871);
    expect(sinStockUnificado, 2881); // = cero + negativos
    expect(sinStockUnificado, total - conStock);
  });

  test('conStock / sinStock / negativo partición', () {
    expect(StockKpi.conStock(1), isTrue);
    expect(StockKpi.sinStock(0), isTrue);
    expect(StockKpi.sinStock(-2), isTrue);
    expect(StockKpi.negativo(-1), isTrue);
    expect(StockKpi.conStock(0), isFalse);
  });
}
