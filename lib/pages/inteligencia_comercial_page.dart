import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/compra_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';

class InteligenciaComercialPage extends StatefulWidget {
  const InteligenciaComercialPage({super.key});

  @override
  State<InteligenciaComercialPage> createState() => _InteligenciaComercialPageState();
}

class _InteligenciaComercialPageState extends State<InteligenciaComercialPage> {
  final RemitoService _remitoService = RemitoService();
  final CompraService _compraService = CompraService();

  List<Map<String, dynamic>> _topRentabilidad = [];
  List<Map<String, dynamic>> _topVendidos = [];
  List<Map<String, dynamic>> _sinMovimiento = [];
  List<Map<String, dynamic>> _agotarse = [];
  List<Map<String, dynamic>> _topClientes = [];
  List<Map<String, dynamic>> _clientesInactivos = [];
  List<Map<String, dynamic>> _topProveedores = [];
  List<Map<String, dynamic>> _ventasMes = [];
  List<Map<String, dynamic>> _comprasMes = [];
  double _gananciaEstimada = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    _topRentabilidad = await db.rawQuery('''
      SELECT descripcion, codigo, costo, precio,
      CASE WHEN costo > 0 THEN ((precio - costo) / costo) * 100 ELSE 0 END AS rentabilidad
      FROM productos
      ORDER BY rentabilidad DESC, descripcion ASC
      LIMIT 10
    ''');
    _topVendidos = await _remitoService.topProductos(limite: 10);
    _sinMovimiento = await db.rawQuery('''
      SELECT p.id, p.codigo, p.descripcion, p.stock
      FROM productos p
      LEFT JOIN movimientos_stock m
        ON m.productoId = p.id
       AND m.tipo = 'salida'
       AND datetime(m.fecha) >= datetime('now', '-30 days')
      WHERE m.id IS NULL
      ORDER BY p.descripcion
      LIMIT 10
    ''');
    _agotarse = await db.rawQuery('''
      SELECT id, codigo, descripcion, stock
      FROM productos
      WHERE stock <= 5
      ORDER BY stock ASC, descripcion
      LIMIT 10
    ''');
    _topClientes = await _remitoService.topClientes(limite: 10);
    _clientesInactivos = await db.rawQuery('''
      SELECT c.id, c.nombre, c.apellido, c.telefono
      FROM clientes c
      LEFT JOIN remitos r
        ON r.clienteId = c.id
       AND r.estado != 'anulado'
       AND datetime(r.fecha) >= datetime('now', '-30 days')
      WHERE r.id IS NULL
      ORDER BY c.nombre
      LIMIT 10
    ''');
    _topProveedores = await db.rawQuery('''
      SELECT proveedorNombre, COUNT(*) AS cantidadCompras, SUM(total) AS totalComprado
      FROM compras
      WHERE estado != 'anulada'
      GROUP BY proveedorNombre
      ORDER BY totalComprado DESC
      LIMIT 10
    ''');
    _ventasMes = await _remitoService.ventasPorMes(meses: 6);
    _comprasMes = await _compraService.comprasPorMes(meses: 6);
    final ganancia = await db.rawQuery('''
      SELECT SUM(ri.subtotal - (ri.cantidad * COALESCE(p.costo, 0))) AS ganancia
      FROM remito_items ri
      JOIN remitos r ON r.id = ri.remitoId
      JOIN productos p ON p.id = ri.productoId
      WHERE r.estado != 'anulado'
        AND datetime(r.fecha) >= datetime('now', '-6 months')
    ''');
    _gananciaEstimada = (ganancia.first['ganancia'] as num?)?.toDouble() ?? 0;

    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Widget _metricCard(String titulo, String valor, IconData icono, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .15),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo),
        subtitle: Text(
          valor,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _listCard(
    String titulo,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) titleBuilder,
    String Function(Map<String, dynamic>) subtitleBuilder,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('Sin datos disponibles.')
            else
              ...items.map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(titleBuilder(item)),
                  subtitle: Text(subtitleBuilder(item)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(String titulo, List<Map<String, dynamic>> data, Color color) {
    final groups = List.generate(data.length, (index) {
      final total = ((data[index]['total'] as num?)?.toDouble() ?? 0);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: total,
            width: 18,
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: data.isEmpty
                  ? const Center(child: Text('Sin datos para graficar.'))
                  : BarChart(
                      BarChartData(
                        barGroups: groups,
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(show: true),
                        alignment: BarChartAlignment.spaceAround,
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              getTitlesWidget: (value, meta) => Text(
                                value >= 1000
                                    ? '${(value / 1000).toStringAsFixed(0)}k'
                                    : value.toStringAsFixed(0),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= data.length) {
                                  return const SizedBox.shrink();
                                }
                                final mes = (data[index]['mes'] ?? '').toString();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    mes.length > 5 ? mes.substring(5) : mes,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Inteligencia comercial',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 1.7,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      _metricCard(
                        'Ganancia estimada (6 meses)',
                        '\$${_gananciaEstimada.toStringAsFixed(0)}',
                        Icons.trending_up_rounded,
                        AppVisuals.success(cs),
                      ),
                      _metricCard(
                        'Productos por agotarse',
                        '${_agotarse.length}',
                        Icons.warning_amber_rounded,
                        AppVisuals.warning(cs),
                      ),
                      _metricCard(
                        'Sin movimiento 30 días',
                        '${_sinMovimiento.length}',
                        Icons.hourglass_empty_rounded,
                        AppVisuals.info(cs),
                      ),
                      _metricCard(
                        'Clientes inactivos',
                        '${_clientesInactivos.length}',
                        Icons.person_off_rounded,
                        AppVisuals.danger(cs),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _chartCard('Ventas por mes', _ventasMes, AppVisuals.primaryAccent(cs)),
                  const SizedBox(height: 12),
                  _chartCard('Compras por mes', _comprasMes, AppVisuals.secondaryAccent(cs)),
                  const SizedBox(height: 12),
                  _listCard(
                    'Top 10 productos por rentabilidad',
                    _topRentabilidad,
                    (item) => '${item['descripcion']} (${item['codigo']})',
                    (item) =>
                        'Costo: \$${((item['costo'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} • Precio: \$${((item['precio'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} • ${(item['rentabilidad'] as num?)?.toStringAsFixed(1) ?? '0'}%',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Top 10 productos más vendidos',
                    _topVendidos,
                    (item) => (item['descripcion'] ?? 'Sin descripción').toString(),
                    (item) =>
                        '${((item['totalVendido'] as num?)?.toInt() ?? 0)} unidades • \$${((item['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Productos sin movimiento',
                    _sinMovimiento,
                    (item) => '${item['descripcion']} (${item['codigo']})',
                    (item) => 'Stock actual: ${item['stock'] ?? 0}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Productos próximos a agotarse',
                    _agotarse,
                    (item) => '${item['descripcion']} (${item['codigo']})',
                    (item) => 'Stock actual: ${item['stock'] ?? 0}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Clientes que más compran',
                    _topClientes,
                    (item) => (item['nombre'] ?? 'Sin nombre').toString(),
                    (item) =>
                        '${((item['cantidadRemitos'] as num?)?.toInt() ?? 0)} remitos • \$${((item['totalCompras'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Clientes inactivos',
                    _clientesInactivos,
                    (item) =>
                        '${item['nombre'] ?? ''} ${(item['apellido'] ?? '').toString()}'.trim(),
                    (item) => 'Teléfono: ${item['telefono'] ?? '-'}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Proveedores con más compras',
                    _topProveedores,
                    (item) => (item['proveedorNombre'] ?? 'Sin proveedor').toString(),
                    (item) =>
                        '${((item['cantidadCompras'] as num?)?.toInt() ?? 0)} compras • \$${((item['totalComprado'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
    );
  }
}
