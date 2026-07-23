import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/cliente.dart';
import '../models/producto.dart';
import '../services/analytics_service.dart';
import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/producto_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import 'cliente_detalle_page.dart';
import 'producto_form_page.dart';
import 'productos_page.dart';

class InteligenciaComercialPage extends StatefulWidget {
  const InteligenciaComercialPage({super.key});

  @override
  State<InteligenciaComercialPage> createState() => _InteligenciaComercialPageState();
}

class _InteligenciaComercialPageState extends State<InteligenciaComercialPage> {
  final CompraService _compraService = CompraService();
  final ProductoService _productoService = ProductoService();
  final ClienteService _clienteService = ClienteService();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _keyAgotarse = GlobalKey();
  final GlobalKey _keySinMovimiento = GlobalKey();
  final GlobalKey _keyClientesInactivos = GlobalKey();
  final GlobalKey _keyGraficos = GlobalKey();

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

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Future<void> _abrirProducto(int? id) async {
    if (id == null) return;
    final todos = await _productoService.obtenerTodos();
    Producto? p;
    for (final e in todos) {
      if (e.id == id) {
        p = e;
        break;
      }
    }
    if (p == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductoFormPage(producto: p)),
    );
    if (mounted) await _cargar();
  }

  Future<void> _abrirCliente(int? id) async {
    if (id == null) return;
    final todos = await _clienteService.obtenerTodos();
    Cliente? c;
    for (final e in todos) {
      if (e.id == id) {
        c = e;
        break;
      }
    }
    if (c == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClienteDetallePage(cliente: c!)),
    );
    if (mounted) await _cargar();
  }

  Future<void> _verProductosPorAgotarse() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProductosPage(soloStockBajoInicial: true),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _verSinMovimiento() async {
    if (_sinMovimiento.isEmpty) {
      await _scrollTo(_keySinMovimiento);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _IntelDetalleListaPage(
          titulo: 'Sin movimiento (30 días)',
          items: _sinMovimiento,
          titleBuilder: (item) =>
              '${item['descripcion']} (${item['codigo']})',
          subtitleBuilder: (item) => 'Stock actual: ${item['stock'] ?? 0}',
          onTap: (item) => _abrirProducto((item['id'] as num?)?.toInt()),
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _verClientesInactivos() async {
    if (_clientesInactivos.isEmpty) {
      await _scrollTo(_keyClientesInactivos);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _IntelDetalleListaPage(
          titulo: 'Clientes inactivos',
          items: _clientesInactivos,
          titleBuilder: (item) =>
              '${item['nombre'] ?? ''} ${(item['apellido'] ?? '').toString()}'
                  .trim(),
          subtitleBuilder: (item) => 'Teléfono: ${item['telefono'] ?? '-'}',
          onTap: (item) => _abrirCliente((item['id'] as num?)?.toInt()),
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    _topRentabilidad = await db.rawQuery('''
      SELECT descripcion, codigo, costo, precio,
      CASE WHEN precio > 0 THEN ((precio - costo) / precio) * 100 ELSE 0 END AS rentabilidad
      FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
      ORDER BY rentabilidad DESC, descripcion ASC
      LIMIT 10
    ''');
    _topVendidos = await AnalyticsService.instance.topProductos(limite: 10);
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
      LIMIT 10
    ''');
    _agotarse = await db.rawQuery('''
      SELECT id, codigo, descripcion, stock
      FROM productos
      WHERE stock <= 5
        AND (deleted_at IS NULL OR deleted_at = '')
      ORDER BY stock ASC, descripcion
      LIMIT 10
    ''');
    _topClientes = await AnalyticsService.instance.topClientes(limite: 10);
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
    _ventasMes = await AnalyticsService.instance.ventasPorMes(meses: 6);
    _comprasMes = await _compraService.comprasPorMes(meses: 6);
    final ahora = DateTime.now();
    _gananciaEstimada = await AnalyticsService.instance.gananciaReal(
      desde: DateTime(ahora.year, ahora.month - 5, 1),
      hasta: ahora,
    );

    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Widget _metricCard(
    String titulo,
    String valor,
    IconData icono,
    Color color, {
    VoidCallback? onTap,
  }) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 10 : 12,
            vertical: wide ? 8 : 10,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: wide ? 16 : 18,
                backgroundColor: color.withValues(alpha: .15),
                child: Icon(icono, color: color, size: wide ? 16 : 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: wide ? 12 : 13,
                        height: 1.15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: wide ? 16 : 17,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listCard(
    String titulo,
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) titleBuilder,
    String Function(Map<String, dynamic>) subtitleBuilder, {
    Key? key,
    void Function(Map<String, dynamic> item)? onItemTap,
    VoidCallback? onVerTodos,
  }) {
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (onVerTodos != null && items.isNotEmpty)
                  TextButton(
                    onPressed: onVerTodos,
                    child: const Text('Ver todos'),
                  ),
              ],
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
                  trailing: onItemTap == null
                      ? null
                      : const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: onItemTap == null ? null : () => onItemTap(item),
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
      appBar: buildModuleAppBar(
        context,
        title: 'Inteligencia comercial',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Inteligencia comercial',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tocá un indicador para ver el detalle.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: MediaQuery.sizeOf(context).width >= 900
                        ? 4
                        : 2,
                    childAspectRatio: MediaQuery.sizeOf(context).width >= 900
                        ? 3.2
                        : 2.4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      _metricCard(
                        'Ganancia real (6 meses)',
                        '\$${_gananciaEstimada.toStringAsFixed(0)}',
                        Icons.trending_up_rounded,
                        AppVisuals.success(cs),
                        onTap: () => _scrollTo(_keyGraficos),
                      ),
                      _metricCard(
                        'Productos por agotarse',
                        '${_agotarse.length}',
                        Icons.warning_amber_rounded,
                        AppVisuals.warning(cs),
                        onTap: _verProductosPorAgotarse,
                      ),
                      _metricCard(
                        'Sin movimiento 30 días',
                        '${_sinMovimiento.length}',
                        Icons.hourglass_empty_rounded,
                        AppVisuals.info(cs),
                        onTap: _verSinMovimiento,
                      ),
                      _metricCard(
                        'Clientes inactivos',
                        '${_clientesInactivos.length}',
                        Icons.person_off_rounded,
                        AppVisuals.danger(cs),
                        onTap: _verClientesInactivos,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _keyGraficos,
                    child: _chartCard(
                      'Ventas por mes',
                      _ventasMes,
                      AppVisuals.primaryAccent(cs),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _chartCard(
                    'Compras por mes',
                    _comprasMes,
                    AppVisuals.secondaryAccent(cs),
                  ),
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
                    (item) =>
                        (item['descripcion'] ?? 'Sin descripción').toString(),
                    (item) =>
                        '${((item['totalVendido'] as num?)?.toInt() ?? 0)} unidades • \$${((item['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Productos sin movimiento',
                    _sinMovimiento,
                    (item) => '${item['descripcion']} (${item['codigo']})',
                    (item) => 'Stock actual: ${item['stock'] ?? 0}',
                    key: _keySinMovimiento,
                    onVerTodos: _verSinMovimiento,
                    onItemTap: (item) =>
                        _abrirProducto((item['id'] as num?)?.toInt()),
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Productos próximos a agotarse',
                    _agotarse,
                    (item) => '${item['descripcion']} (${item['codigo']})',
                    (item) => 'Stock actual: ${item['stock'] ?? 0}',
                    key: _keyAgotarse,
                    onVerTodos: _verProductosPorAgotarse,
                    onItemTap: (item) =>
                        _abrirProducto((item['id'] as num?)?.toInt()),
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Clientes que más compran',
                    _topClientes,
                    (item) => (item['nombre'] ?? 'Sin nombre').toString(),
                    (item) =>
                        '${((item['cantidadOps'] as num?)?.toInt() ?? (item['cantidadRemitos'] as num?)?.toInt() ?? 0)} operaciones • \$${((item['totalCompras'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                    onItemTap: (item) => _abrirCliente(
                      (item['clienteId'] as num?)?.toInt() ??
                          (item['id'] as num?)?.toInt(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Clientes inactivos',
                    _clientesInactivos,
                    (item) =>
                        '${item['nombre'] ?? ''} ${(item['apellido'] ?? '').toString()}'
                            .trim(),
                    (item) => 'Teléfono: ${item['telefono'] ?? '-'}',
                    key: _keyClientesInactivos,
                    onVerTodos: _verClientesInactivos,
                    onItemTap: (item) =>
                        _abrirCliente((item['id'] as num?)?.toInt()),
                  ),
                  const SizedBox(height: 12),
                  _listCard(
                    'Proveedores con más compras',
                    _topProveedores,
                    (item) =>
                        (item['proveedorNombre'] ?? 'Sin proveedor').toString(),
                    (item) =>
                        '${((item['cantidadCompras'] as num?)?.toInt() ?? 0)} compras • \$${((item['totalComprado'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
    );
  }
}

/// Lista completa al tocar un KPI de inteligencia comercial.
class _IntelDetalleListaPage extends StatelessWidget {
  final String titulo;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) titleBuilder;
  final String Function(Map<String, dynamic>) subtitleBuilder;
  final Future<void> Function(Map<String, dynamic> item)? onTap;

  const _IntelDetalleListaPage({
    required this.titulo,
    required this.items,
    required this.titleBuilder,
    required this.subtitleBuilder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: titulo),
      body: items.isEmpty
          ? const Center(child: Text('Sin datos disponibles.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text(titleBuilder(item)),
                  subtitle: Text(subtitleBuilder(item)),
                  trailing: onTap == null
                      ? null
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: onTap == null ? null : () => onTap!(item),
                );
              },
            ),
    );
  }
}
