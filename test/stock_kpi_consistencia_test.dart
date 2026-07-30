import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_nuevo/core/inventory/stock_kpi.dart';

/// Invariante: Productos / Inicio / Dashboard usan el mismo criterio.
void main() {
  test('StockKpi: con + sin == total (incluye negativos en sin)', () {
    final stocks = <int>[
      4, 10, 3, 3, 3, // 5 con stock
      -2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 12 negativos
      for (var i = 0; i < 2866; i++) 0,
    ];
    expect(stocks.length, 2883);

    final con = stocks.where(StockKpi.conStock).length;
    final sin = stocks.where(StockKpi.sinStock).length;
    final neg = stocks.where(StockKpi.negativo).length;

    expect(con, 5);
    expect(neg, 12);
    expect(sin, 2878);
    expect(con + sin, 2883);
  });

  test('bug viejo ==0 excluía negativos del total parcial', () {
    final stocks = [-2, -1, 0, 0, 5];
    final viejoSin = stocks.where((s) => s == 0).length;
    final viejoCon = stocks.where((s) => s > 0).length;
    expect(viejoCon + viejoSin, isNot(stocks.length));
    expect(
      stocks.where(StockKpi.conStock).length +
          stocks.where(StockKpi.sinStock).length,
      stocks.length,
    );
  });
}
