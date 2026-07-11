import '../database/database_helper.dart';

/// Línea de sugerencia de compra según ventas históricas y stock.
class SugerenciaPedido {
  final int productoId;
  final String codigo;
  final String articulo;
  final String proveedor;
  final String categoria;
  final String marca;
  final String modelo;
  final String color;
  final String talle;
  final int cantidadVendida;
  final int stockActual;
  final int stockMinimo;
  final int cantidadSugerida;

  const SugerenciaPedido({
    required this.productoId,
    required this.codigo,
    required this.articulo,
    required this.proveedor,
    required this.categoria,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.talle,
    required this.cantidadVendida,
    required this.stockActual,
    required this.stockMinimo,
    required this.cantidadSugerida,
  });

  SugerenciaPedido copyWith({int? cantidadSugerida}) {
    return SugerenciaPedido(
      productoId: productoId,
      codigo: codigo,
      articulo: articulo,
      proveedor: proveedor,
      categoria: categoria,
      marca: marca,
      modelo: modelo,
      color: color,
      talle: talle,
      cantidadVendida: cantidadVendida,
      stockActual: stockActual,
      stockMinimo: stockMinimo,
      cantidadSugerida: cantidadSugerida ?? this.cantidadSugerida,
    );
  }
}

/// Analiza ventas (remitos + facturas) entre fechas y sugiere qué comprar.
class PedidoSugeridoService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Fórmula: cubrir lo vendido y dejar stock mínimo.
  /// `sugerido = max(0, vendido + stockMinimo - stockActual)`.
  static int calcularSugerido({
    required int vendido,
    required int stock,
    required int stockMinimo,
  }) {
    final s = vendido + stockMinimo - stock;
    return s < 0 ? 0 : s;
  }

  Future<List<SugerenciaPedido>> analizar({
    required DateTime desde,
    required DateTime hasta,
    String? proveedor,
    String? categoria,
    String? marca,
    String? modelo,
    String? color,
    String? talle,
    bool soloConSugerencia = true,
  }) async {
    final db = await _dbHelper.database;
    final desdeIso = DateTime(desde.year, desde.month, desde.day)
        .toIso8601String();
    final hastaIso = DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59)
        .toIso8601String();

    final filtrosProd = <String>[
      "(p.deleted_at IS NULL OR p.deleted_at = '')",
    ];
    final argsProd = <Object?>[];

    void addFiltro(String col, String? valor) {
      final v = valor?.trim() ?? '';
      if (v.isEmpty) return;
      filtrosProd.add('LOWER(TRIM(p.$col)) = ?');
      argsProd.add(v.toLowerCase());
    }

    addFiltro('proveedor', proveedor);
    addFiltro('categoria', categoria);
    addFiltro('marca', marca);
    addFiltro('modelo', modelo);
    addFiltro('color_producto', color);
    addFiltro('talle', talle);

    final whereProd = filtrosProd.join(' AND ');

    final rows = await db.rawQuery('''
      SELECT
        p.id AS productoId,
        p.codigo AS codigo,
        p.descripcion AS articulo,
        COALESCE(p.proveedor, '') AS proveedor,
        COALESCE(p.categoria, '') AS categoria,
        COALESCE(p.marca, '') AS marca,
        COALESCE(p.modelo, '') AS modelo,
        COALESCE(p.color_producto, '') AS color,
        COALESCE(p.talle, '') AS talle,
        COALESCE(p.stock, 0) AS stockActual,
        COALESCE(p.stock_minimo, 0) AS stockMinimo,
        COALESCE(v.totalVendido, 0) AS cantidadVendida
      FROM productos p
      INNER JOIN (
        SELECT productoId, SUM(cantidad) AS totalVendido
        FROM (
          SELECT ri.productoId AS productoId, ri.cantidad AS cantidad
          FROM remito_items ri
          JOIN remitos r ON r.id = ri.remitoId
          WHERE r.estado != 'anulado'
            AND r.fecha >= ?
            AND r.fecha <= ?
          UNION ALL
          SELECT vi.productoId, vi.cantidad
          FROM ventas_items vi
          JOIN ventas v ON v.id = vi.ventaId
          WHERE v.estado != 'anulada'
            AND v.tipo NOT IN ('presupuesto')
            AND v.fecha >= ?
            AND v.fecha <= ?
        )
        GROUP BY productoId
      ) v ON v.productoId = p.id
      WHERE $whereProd
      ORDER BY v.totalVendido DESC, p.descripcion COLLATE NOCASE ASC
    ''', [desdeIso, hastaIso, desdeIso, hastaIso, ...argsProd]);

    final out = <SugerenciaPedido>[];
    for (final row in rows) {
      final vendido = (row['cantidadVendida'] as num?)?.toInt() ?? 0;
      final stock = (row['stockActual'] as num?)?.toInt() ?? 0;
      final minimo = (row['stockMinimo'] as num?)?.toInt() ?? 0;
      final sugerido = calcularSugerido(
        vendido: vendido,
        stock: stock,
        stockMinimo: minimo,
      );
      if (soloConSugerencia && sugerido <= 0) continue;
      out.add(
        SugerenciaPedido(
          productoId: (row['productoId'] as num).toInt(),
          codigo: row['codigo']?.toString() ?? '',
          articulo: row['articulo']?.toString() ?? '',
          proveedor: row['proveedor']?.toString() ?? '',
          categoria: row['categoria']?.toString() ?? '',
          marca: row['marca']?.toString() ?? '',
          modelo: row['modelo']?.toString() ?? '',
          color: row['color']?.toString() ?? '',
          talle: row['talle']?.toString() ?? '',
          cantidadVendida: vendido,
          stockActual: stock,
          stockMinimo: minimo,
          cantidadSugerida: sugerido,
        ),
      );
    }
    return out;
  }

  Future<List<String>> valoresDistintos(String columna) async {
    final permitidas = {
      'proveedor',
      'categoria',
      'marca',
      'modelo',
      'color_producto',
      'talle',
    };
    if (!permitidas.contains(columna)) return [];
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT TRIM($columna) AS v
      FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
        AND TRIM(COALESCE($columna, '')) != ''
      ORDER BY v COLLATE NOCASE ASC
    ''');
    return rows.map((r) => r['v']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
}
