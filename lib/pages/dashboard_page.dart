import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/producto.dart';
import '../services/analytics_service.dart';
import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import 'clientes_deudores_page.dart';
import 'clientes_page.dart';
import 'compras_page.dart';
import 'productos_page.dart';
import 'proveedores_page.dart';
import 'remitos_page.dart';
import 'ventas_page.dart';

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
  final CuentaCorrienteService cuentaCorrienteService =
      CuentaCorrienteService();
  final AnalyticsService analytics = AnalyticsService.instance;

  int totalProductos = 0;
  int totalClientes = 0;
  int totalRemitos = 0;
  int totalProveedores = 0;
  int productosCriticos = 0;
  int productosSinStock = 0;
  int productosBajoMargen = 0;
  double totalVentas = 0;
  double ventasHoy = 0;
  double ventasMes = 0;
  double comprasMes = 0;
  double gananciaMes = 0;
  double gananciaTotal = 0;
  double valorStock = 0;
  List<Map<String, dynamic>> productosTop = [];
  List<Map<String, dynamic>> clientesTop = [];
  List<Map<String, dynamic>> ventasMensuales = [];
  List<Producto> sinStock = [];
  List<Producto> bajoMargen = [];
  ResumenCuentasCobrar? resumenCc;
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
    final proveedores = await proveedorService.cantidad();

    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final inicioMes = DateTime(ahora.year, ahora.month, 1);

    final ventas = await analytics.ventasTotales();
    final topProductos = await analytics.topProductos();
    final topClientes = await analytics.topClientes();
    final ventasMeses = await analytics.ventasPorMes(meses: 6);
    final ventasDelDia = await analytics.ventasTotales(desde: inicioDia, hasta: ahora);
    final ventasDelMes = await analytics.ventasTotales(desde: inicioMes, hasta: ahora);
    final gananciaDelMes = await analytics.gananciaReal(desde: inicioMes, hasta: ahora);
    final gananciaAll = await analytics.gananciaReal();
    final comprasDelMes = await compraService.totalComprasPorPeriodo(inicioMes, ahora);
    final resumen = await cuentaCorrienteService.resumenDashboard();
    final margenBajo = await analytics.productosBajoMargen(umbralPorcentaje: 15);

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
      gananciaMes = gananciaDelMes;
      gananciaTotal = gananciaAll;
      valorStock = stock;
      productosTop = topProductos;
      clientesTop = topClientes;
      ventasMensuales = ventasMeses;
      productosCriticos = criticos;
      productosSinStock = sinStockCount;
      productosBajoMargen = margenBajo.length;
      sinStock = agotados.take(5).toList();
      bajoMargen = margenBajo.take(5).toList();
      resumenCc = resumen;
      cargando = false;
    });
  }

  Widget _cuentasPorCobrarCard(
    ColorScheme cs,
    ResumenCuentasCobrar resumen,
  ) {
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ClientesDeudoresPage(),
            ),
          ).then((_) => cargar());
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        AppVisuals.danger(cs).withValues(alpha: .15),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppVisuals.danger(cs),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cuentas por cobrar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '\$${resumen.montoTotalPendiente.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppVisuals.danger(cs),
                ),
              ),
              const SizedBox(height: 8),
              Text('${resumen.clientesConDeuda} clientes'),
              Text('${resumen.ventasPendientes} ventas pendientes'),
              if (resumen.mayorDeudor != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Mayor deuda: ${resumen.mayorDeudor!.nombre} '
                  '(\$${resumen.mayorDeudor!.saldoPendiente.toStringAsFixed(2)})',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
    VoidCallback? onTap,
  }) {
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(icono, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(fontSize: 10, color: labelColor, height: 1.1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: labelColor, size: 14),
            ],
          ),
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
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
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

  Widget _chartCard(Color ventasColor, Color gananciaColor) {
    final groups = List.generate(ventasMensuales.length, (index) {
      final total = ((ventasMensuales[index]['total'] as num?)?.toDouble() ?? 0);
      final ganancia =
          ((ventasMensuales[index]['ganancia'] as num?)?.toDouble() ?? 0);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: total,
            color: ventasColor,
            width: 12,
            borderRadius: BorderRadius.circular(4),
          ),
          BarChartRodData(
            toY: ganancia < 0 ? 0 : ganancia,
            color: gananciaColor,
            width: 12,
            borderRadius: BorderRadius.circular(4),
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
              'Ventas y ganancia · últimos 6 meses',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _legendDot(ventasColor, 'Ventas'),
                const SizedBox(width: 16),
                _legendDot(gananciaColor, 'Ganancia real'),
              ],
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
                        gridData: const FlGridData(show: true),
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
                                if (index < 0 ||
                                    index >= ventasMensuales.length) {
                                  return const SizedBox.shrink();
                                }
                                final mes = (ventasMensuales[index]['mes'] ?? '')
                                    .toString();
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

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
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
      appBar: buildModuleAppBar(
        context,
        title: 'Dashboard',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargar,
          ),
        ],
      ),
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
                    if (resumenCc != null) ...[
                      _cuentasPorCobrarCard(colorScheme, resumenCc!),
                      const SizedBox(height: 12),
                      if (resumenCc!.alertas.isNotEmpty) ...[
                        Text(
                          'Alertas de cuenta corriente',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...resumenCc!.alertas.map((a) {
                          final color = a.contains('debe')
                              ? AppVisuals.danger(colorScheme)
                              : a.contains('vencen')
                                  ? AppVisuals.warning(colorScheme)
                                  : AppVisuals.warning(colorScheme);
                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.warning_amber_rounded,
                                  color: color),
                              title: Text(a),
                              dense: true,
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cols = w >= 1100
                            ? 4
                            : w >= 720
                                ? 3
                                : 2;
                        final aspect = cols >= 4
                            ? 4.2
                            : cols == 3
                                ? 3.6
                                : 3.2;
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: aspect,
                          children: [
                        _statCard(
                          titulo: 'Productos',
                          valor: '$totalProductos',
                          icono: Icons.inventory_2_rounded,
                          color: productosColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductosPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Clientes',
                          valor: '$totalClientes',
                          icono: Icons.groups_rounded,
                          color: clientesColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ClientesPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Remitos',
                          valor: '$totalRemitos',
                          icono: Icons.description_rounded,
                          color: remitosColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RemitosPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Proveedores activos',
                          valor: '$totalProveedores',
                          icono: Icons.local_shipping_rounded,
                          color: AppVisuals.info(colorScheme),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProveedoresPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Ventas del día',
                          valor: '\$${ventasHoy.toStringAsFixed(0)}',
                          icono: Icons.today_rounded,
                          color: ventasColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VentasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Ventas del mes',
                          valor: '\$${ventasMes.toStringAsFixed(0)}',
                          icono: Icons.calendar_month_rounded,
                          color: ventasColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VentasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Compras del mes',
                          valor: '\$${comprasMes.toStringAsFixed(0)}',
                          icono: Icons.shopping_cart_rounded,
                          color: stockColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ComprasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Productos críticos',
                          valor: '$productosCriticos',
                          icono: Icons.warning_amber_rounded,
                          color: sinStockColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductosPage(
                                  soloStockBajoInicial: true,
                                ),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Productos sin stock',
                          valor: '$productosSinStock',
                          icono: Icons.remove_shopping_cart_rounded,
                          color: sinStockColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductosPage(
                                  soloSinStockInicial: true,
                                ),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Ganancia del mes',
                          valor: '\$${gananciaMes.toStringAsFixed(0)}',
                          icono: Icons.trending_up_rounded,
                          color: AppVisuals.success(colorScheme),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VentasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Ganancia total',
                          valor: '\$${gananciaTotal.toStringAsFixed(0)}',
                          icono: Icons.savings_rounded,
                          color: AppVisuals.success(colorScheme),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VentasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Bajo margen (<15%)',
                          valor: '$productosBajoMargen',
                          icono: Icons.percent_rounded,
                          color: AppVisuals.warning(colorScheme),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductosPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                        _statCard(
                          titulo: 'Total ventas',
                          valor: '\$${totalVentas.toStringAsFixed(0)}',
                          icono: Icons.payments_rounded,
                          color: ventasColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const VentasPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                      ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 3,
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProductosPage(),
                            ),
                          ).then((_) => cargar());
                        },
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
                    _chartCard(ventasColor, AppVisuals.tertiaryAccent(colorScheme)),
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
                              '${((producto['totalVendido'] as num?)?.toInt() ?? 0)} u. · '
                              'Gan. \$${((producto['totalGanancia'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          valor:
                              '\$${((producto['totalMonto'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          icono: Icons.sell_rounded,
                          color: topProductosColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductosPage(),
                              ),
                            ).then((_) => cargar());
                          },
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
                              '${((cliente['cantidadOps'] as num?)?.toInt() ?? (cliente['cantidadRemitos'] as num?)?.toInt() ?? 0)} operaciones',
                          valor:
                              '\$${((cliente['totalCompras'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                          icono: Icons.workspace_premium_rounded,
                          color: topClientesColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ClientesPage(),
                              ),
                            ).then((_) => cargar());
                          },
                        ),
                      ),
                    if (bajoMargen.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Alertas de bajo margen',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...bajoMargen.map(
                        (p) => Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProductosPage(),
                                ),
                              ).then((_) => cargar());
                            },
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppVisuals.warning(colorScheme).withValues(alpha: .15),
                              child: Icon(
                                Icons.percent_rounded,
                                color: AppVisuals.warning(colorScheme),
                              ),
                            ),
                            title: Text(p.descripcion),
                            subtitle: Text(
                              'Margen ${p.margenPorcentaje.toStringAsFixed(1)}% · '
                              'Costo \$${p.costo.toStringAsFixed(2)} · '
                              'Precio \$${p.precio.toStringAsFixed(2)}',
                            ),
                          ),
                        ),
                      ),
                    ],
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
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProductosPage(),
                                ),
                              ).then((_) => cargar());
                            },
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
