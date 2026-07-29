import 'package:flutter_test/flutter_test.dart';

/// Invariante de KPIs Productos: con + sin == total.
/// Campo: stock negativo no entraba en "Sin stock" (== 0) ni en "Con stock"
/// (> 0) → 2866+5 ≠ 2883 con exactamente 12 negativos.
void main() {
  test('conteo stock: con (>0) + sin (<=0) == total', () {
    final stocks = <int>[
      4, 10, 3, 3, 3, // 5 con stock
      -2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 12 negativos
      for (var i = 0; i < 2866; i++) 0,
    ];
    expect(stocks.length, 2883);

    final con = stocks.where((s) => s > 0).length;
    final sinSoloCero = stocks.where((s) => s == 0).length;
    final sinIncluyeNeg = stocks.where((s) => s <= 0).length;
    final neg = stocks.where((s) => s < 0).length;

    expect(con, 5);
    expect(neg, 12);
    expect(sinSoloCero, 2866);
    // Bug viejo (como en tu captura):
    expect(con + sinSoloCero, 2871);
    expect(con + sinSoloCero, isNot(2883));
    // Fix:
    expect(con + sinIncluyeNeg, 2883);
    expect(sinIncluyeNeg, 2878);
  });
}
