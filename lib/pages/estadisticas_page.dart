import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/analytics_service.dart';
import '../services/compra_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

enum _PeriodoEstadisticas { dias30, dias90, meses6, anio }

class EstadisticasPage extends StatefulWidget {
  const EstadisticasPage({super.key});

  @override
  State<EstadisticasPage> createState() => _EstadisticasPageState();
}

class _EstadisticasPageState extends State<EstadisticasPage> {
  final CompraService _compraService = CompraService();

  _PeriodoEstadisticas _periodo = _PeriodoEstadisticas.meses6;
  bool _cargando = true;

  double _ventas = 0;
  double _ganancia = 0;
  List<Map<String, dynamic>> _masVendidos = [];
  List<Map<String, dynamic>> _menosVendidos = [];
  List<Map<String, dynamic>> _rentabilidad = [];
  List<Map<String, dynamic>> _sinMovimiento = [];
  List<Map<String, dynamic>> _stockCritico = [];
  List<Map<String, dynamic>> _ventasMes = [];
  List<Map<String, dynamic>> _comprasMes = [];

  (DateTime desde, DateTime hasta) _rango() {
    final hasta = DateTime.now();
    switch (_periodo) {
      case _PeriodoEstadisticas.dias30:
        return (hasta.subtract(const Duration(days: 30)), hasta);
      case _PeriodoEstadisticas.dias90:
        return (hasta.subtract(const Duration(days: 90)), hasta);
      case _PeriodoEstadisticas.meses6:
        return (DateTime(hasta.year, hasta.month - 5, 1), hasta);
      case _PeriodoEstadisticas.anio:
        return (DateTime(hasta.year - 1, hasta.month, hasta.day), hasta);
    }
  }

  int get _mesesGrafico {
    switch (_periodo) {
      case _PeriodoEstadisticas.dias30:
        return 2;
      case _PeriodoEstadisticas.dias90:
        return 4;
      case _PeriodoEstadisticas.meses6:
        return 6;
      case _PeriodoEstadisticas.anio:
        return 12;
    }
  }

  String get _labelPeriodo {
    switch (_periodo) {
      case _PeriodoEstadisticas.dias30:
        return 'Últimos 30 días';
      case _PeriodoEstadisticas.dias90:
        return 'Últimos 90 días';
      case _PeriodoEstadisticas.meses6:
        return 'Últimos 6 meses';
      case _PeriodoEstadisticas.anio:
        return 'Último año';
    }
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final (desde, hasta) = _rango();
    final db = await DatabaseHelper.instance.database;
    final analytics = AnalyticsService.instance;

    _ventas = await analytics.ventasTotales(desde: desde, hasta: hasta);
    _ganancia = await analytics.gananciaReal(desde: desde, hasta: hasta);
    _masVendidos = await analytics.topProductos(
      limite: 10,
      desde: desde,
      hasta: hasta,
    );
    _menosVendidos = await analytics.bottomProductos(
      limite: 10,
      desde: desde,
      hasta: hasta,
    );
    _rentabilidad = await db.rawQuery('''
      SELECT descripcion, codigo, costo, precio,
        CASE WHEN precio > 0 THEN ((precio - costo) / precio) * 100 ELSE 0 END AS rentabilidad
      FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
        AND precio > 0
      ORDER BY rentabilidad DESC, descripcion ASC
      LIMIT 10
    ''');
    _sinMovimiento = await db.rawQuery('''
      SELECT p.id, p.codigo, p.descripcion, p.stock
      FROM productos p
      LEFT JOIN movimientos_stock m
        ON m.productoId = p.id
       AND m.tipo = 'salida'
       AND datetime(m.fecha) >= datetime('now', '-30 days')
      WHERE m.id IS NULL
        AND (p.deleted_at IS NULL OR p.deleted_at = '')
      ORDER BY p.descripcion
      LIMIT 15
    ''');
    _stockCritico = await db.rawQuery('''
      SELECT id, codigo, descripcion, stock, stock_minimo
      FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
        AND (
          (stock_minimo IS NOT NULL AND stock_minimo > 0 AND stock <= stock_minimo)
          OR ((stock_minimo IS NULL OR stock_minimo <= 0) AND stock <= 5)
        )
      ORDER BY stock ASC, descripcion
      LIMIT 15
    ''');
    _ventasMes = await analytics.ventasPorMes(meses: _mesesGrafico);
    _comprasMes = await _compraService.comprasPorMes(meses: _mesesGrafico);

    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .15),
              child: Icon(icono, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    valor,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista(
    String titulo,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) tituloItem,
    String Function(Map<String, dynamic>) detalle,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Sin datos en el período.'),
              )
            else
              ...items.map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tituloItem(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(detalle(item)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chart(String titulo, List<Map<String, dynamic>> data, Color color) {
    if (data.isEmpty) {
      return Card(
        child: ListTile(
          title: Text(titulo),
          subtitle: const Text('Sin datos para graficar'),
        ),
      );
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final total = (data[i]['total'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), total));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= data.length) {
                            return const SizedBox.shrink();
                          }
                          final mes = '${data[i]['mes'] ?? ''}'.split('-').last;
                          return Text(mes, style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: .12),
                      ),
                    ),
                  ],
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
    final margen = _ventas > 0 ? (_ganancia / _ventas) * 100 : 0.0;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Estadísticas',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                for (final p in _PeriodoEstadisticas.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (p) {
                        _PeriodoEstadisticas.dias30 => '30 días',
                        _PeriodoEstadisticas.dias90 => '90 días',
                        _PeriodoEstadisticas.meses6 => '6 meses',
                        _PeriodoEstadisticas.anio => '1 año',
                      }),
                      selected: _periodo == p,
                      onSelected: (_) {
                        setState(() => _periodo = p);
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        Text(
                          _labelPeriodo,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _kpi(
                          'Ventas',
                          '\$${_ventas.toStringAsFixed(0)}',
                          Icons.point_of_sale_rounded,
                          AppVisuals.primaryAccent(cs),
                        ),
                        _kpi(
                          'Ganancia real',
                          '\$${_ganancia.toStringAsFixed(0)}',
                          Icons.trending_up_rounded,
                          AppVisuals.success(cs),
                        ),
                        _kpi(
                          'Margen sobre ventas',
                          '${margen.toStringAsFixed(1)}%',
                          Icons.percent_rounded,
                          AppVisuals.info(cs),
                        ),
                        const SizedBox(height: 4),
                        _chart(
                          'Evolución de ventas',
                          _ventasMes,
                          AppVisuals.primaryAccent(cs),
                        ),
                        const SizedBox(height: 8),
                        _chart(
                          'Evolución de compras',
                          _comprasMes,
                          AppVisuals.secondaryAccent(cs),
                        ),
                        const SizedBox(height: 8),
                        _lista(
                          'Más vendidos',
                          _masVendidos,
                          (i) => '${i['descripcion'] ?? ''}',
                          (i) =>
                              'Cant: ${((i['totalVendido'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} · \$ ${((i['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} · Gan \$ ${((i['totalGanancia'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                        ),
                        const SizedBox(height: 8),
                        _lista(
                          'Menos vendidos (con movimiento)',
                          _menosVendidos,
                          (i) => '${i['descripcion'] ?? ''}',
                          (i) =>
                              'Cant: ${((i['totalVendido'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} · \$ ${((i['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                        ),
                        const SizedBox(height: 8),
                        _lista(
                          'Mayor rentabilidad (lista)',
                          _rentabilidad,
                          (i) => '${i['descripcion']} (${i['codigo']})',
                          (i) =>
                              '${((i['rentabilidad'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}% · Costo \$ ${((i['costo'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} · Precio \$ ${((i['precio'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 8),
                        _lista(
                          'Sin movimiento (30 días)',
                          _sinMovimiento,
                          (i) => '${i['descripcion']} (${i['codigo']})',
                          (i) => 'Stock: ${i['stock']}',
                        ),
                        const SizedBox(height: 8),
                        _lista(
                          'Stock crítico',
                          _stockCritico,
                          (i) => '${i['descripcion']} (${i['codigo']})',
                          (i) => 'Stock: ${i['stock']}',
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
