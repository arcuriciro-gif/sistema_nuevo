import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/producto.dart';
import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ProductoService productoService = ProductoService();
  final ClienteService clienteService = ClienteService();
  final RemitoService remitoService = RemitoService();
  final CompraService compraService = CompraService();
  final ProveedorService proveedorService = ProveedorService();

  int totalProductos = 0;
  int totalClientes = 0;
  int totalRemitos = 0;
  int totalProveedores = 0;
  int productosCriticos = 0;
  int productosSinStock = 0;
  double totalVentas = 0;
  double ventasHoy = 0;
  double ventasMes = 0;
  double comprasMes = 0;
  double valorStock = 0;
  List<Map<String, dynamic>> productosTop = [];
  List<Map<String, dynamic>> clientesTop = [];
  List<Map<String, dynamic>> ventasMensuales = [];
  List<Producto> sinStock = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    cargar();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() => cargando = true);

    final productos = await productoService.obtenerTodos();
    final clientes = await clienteService.obtenerTodos();
    final remitos = await remitoService.cantidad();
    final ventas = await remitoService.totalVentas();
    final topProductos = await remitoService.topProductos();
    final topClientes = await remitoService.topClientes();
    final ventasMeses = await remitoService.ventasPorMes(meses: 6);
    final proveedores = await proveedorService.cantidad();

    final ahora = DateTime.now();
    final ventasDelDia = await remitoService.totalVentasPorPeriodo(
      DateTime(ahora.year, ahora.month, ahora.day),
      ahora,
    );
    final ventasDelMes = await remitoService.totalVentasPorPeriodo(
      DateTime(ahora.year, ahora.month, 1),
      ahora,
    );
    final comprasDelMes = await compraService.totalComprasPorPeriodo(
      DateTime(ahora.year, ahora.month, 1),
      ahora,
    );

    double stock = 0;
    List<Producto> agotados = [];
    int criticos = 0;
    int sinStockCount = 0;
    for (final p in productos) {
      stock += p.precio * p.stock;
      if (p.stock <= 5) criticos++;
      if (p.stock == 0) {
        sinStockCount++;
        agotados.add(p);
      }
    }

    if (!mounted) return;
    setState(() {
      totalProductos = productos.length;
      totalClientes = clientes.length;
      totalRemitos = remitos;
      totalProveedores = proveedores;
      totalVentas = ventas;
      ventasHoy = ventasDelDia;
      ventasMes = ventasDelMes;
      comprasMes = comprasDelMes;
      valorStock = stock;
      productosTop = topProductos;
      clientesTop = topClientes;
      ventasMensuales = ventasMeses;
      productosCriticos = criticos;
      productosSinStock = sinStockCount;
      sinStock = agotados.take(5).toList();
      cargando = false;
    });
  }

  Widget _statCard({
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
  }) {
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .15),
                  radius: 20,
                  child: Icon(icono, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(fontSize: 13, color: labelColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              valor,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankingCard({
    required String titulo,
    required String subtitulo,
    required String valor,
    required IconData icono,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .15),
          child: Icon(icono, color: color),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitulo),
        trailing: Text(
          valor,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  Widget _chartCard(Color color) {
    final groups = List.generate(ventasMensuales.length, (index) {
      final total = ((ventasMensuales[index]['total'] as num?)?.toDouble() ?? 0);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: total,
            color: color,
            width: 18,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    });

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ventas últimos 6 meses',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: ventasMensuales.isEmpty
                  ? const Center(child: Text('Sin datos para graficar'))
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
                                if (index < 0 || index >= ventasMensuales.length) {
                                  return const SizedBox.shrink();
                                }
                                final mes =
                                    (ventasMensuales[index]['mes'] ?? '').toString();
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final productosColor = AppVisuals.primaryAccent(colorScheme);
    final clientesColor = AppVisuals.secondaryAccent(colorScheme);
    final remitosColor = AppVisuals.info(colorScheme);
    final ventasColor = AppVisuals.success(colorScheme);
    final stockColor = AppVisuals.warning(colorScheme);
    final topProductosColor = AppVisuals.tertiaryAccent(colorScheme);
    final topClientesColor = AppVisuals.info(colorScheme);
    final sinStockColor = AppVisuals.danger(colorScheme);

    return Scaffold(
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen general',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.2,
                      children: [
                        _statCard(
                          titulo: 'Productos',
                          valor: '$totalProductos',
                          icono: Icons.inventory_2_rounded,
                          color: productosColor,
                        ),
                        _statCard(
                          titulo: 'Clientes',
                          valor: '$totalClientes',
                          icono: Icons.groups_rounded,
                          color: clientesColor,
                        ),
                        _statCard(
                          titulo: 'Remitos',
                          valor: '$totalRemitos',
                          icono: Icons.description_rounded,
                          color: remitosColor,
                        ),
                        _statCard(
                          titulo: 'Proveedores activos',
                          valor: '$totalProveedores',
                          icono: Icons.local_shipping_rounded,
                          color: AppVisuals.info(colorScheme),
                        ),
                        _statCard(
                          titulo: 'Ventas del día',
                          valor: '\$${ventasHoy.toStringAsFixed(0)}',
                          icono: Icons.today_rounded,
                          color: ventasColor,
                        ),
                        _statCard(
                          titulo: 'Ventas del mes',
                          valor: '\$${ventasMes.toStringAsFixed(0)}',
                          icono: Icons.calendar_month_rounded,
                          color: ventasColor,
                        ),
                        _statCard(
                          titulo: 'Compras del mes',
                          valor: '\$${comprasMes.toStringAsFixed(0)}',
                          icono: Icons.shopping_cart_rounded,
                          color: stockColor,
                        ),
                        _statCard(
                          titulo: 'Productos críticos',
                          valor: '$productosCriticos',
                          icono: Icons.warning_amber_rounded,
                          color: sinStockColor,
                        ),
                        _statCard(
                          titulo: 'Productos sin stock',
                          valor: '$productosSinStock',
                          icono: Icons.remove_shopping_cart_rounded,
                          color: sinStockColor,
                        ),
                        _statCard(
                          titulo: 'Total ventas',
                          valor: '\$${totalVentas.toStringAsFixed(0)}',
                          icono: Icons.payments_rounded,
                          color: ventasColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 3,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: stockColor.withValues(alpha: .15),
                          child: Icon(Icons.warehouse_rounded, color: stockColor),
                        ),
                        title: const Text('Valor del stock'),
                        subtitle: const Text('Precio de venta × cantidad'),
                        trailing: Text(
                          '\$${valorStock.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: stockColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _chartCard(ventasColor),
                    const SizedBox(height: 20),
                    Text(
                      'Top 5 productos más vendidos',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (productosTop.isEmpty)
                      const Card(child: ListTile(title: Text('Sin ventas registradas')))
                    else
                      ...productosTop.map(
                        (producto) => _rankingCard(
                          titulo: (producto['descripcion'] ?? 'Sin descripción')
                              .toString(),
                          subtitulo:
                              '${((producto['totalVendido'] as num?)?.toInt() ?? 0)} unidades vendidas',
                          valor:
                              '\$${((producto['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          icono: Icons.sell_rounded,
                          color: topProductosColor,
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Top 5 clientes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (clientesTop.isEmpty)
                      const Card(child: ListTile(title: Text('Sin clientes con compras')))
                    else
                      ...clientesTop.map(
                        (cliente) => _rankingCard(
                          titulo: (cliente['nombre'] ?? 'Sin nombre').toString(),
                          subtitulo:
                              '${((cliente['cantidadRemitos'] as num?)?.toInt() ?? 0)} remitos',
                          valor:
                              '\$${((cliente['totalCompras'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          icono: Icons.workspace_premium_rounded,
                          color: topClientesColor,
                        ),
                      ),
                    if (sinStock.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Productos sin stock',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...sinStock.map(
                        (p) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: sinStockColor.withValues(alpha: .15),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                color: sinStockColor,
                              ),
                            ),
                            title: Text(p.descripcion),
                            subtitle: Text(p.codigo),
                            trailing: Text(
                              'SIN STOCK',
                              style: TextStyle(
                                color: sinStockColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
