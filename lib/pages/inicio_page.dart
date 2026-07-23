import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/media_avatar.dart';
import 'calculadora_page.dart';
import 'clientes_deudores_page.dart';
import 'clientes_page.dart';
import 'compras_page.dart';
import 'productos_page.dart';
import 'ventas_page.dart';
import 'ventas_totales_page.dart';

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  final _productoService = ProductoService();
  final _clienteService = ClienteService();
  final _remitoService = RemitoService();
  final _compraService = CompraService();
  final _ccService = CuentaCorrienteService();

  int _totalProductos = 0;
  int _stockTotal = 0;
  int _sinStock = 0;
  int _conStock = 0;
  int _totalClientes = 0;
  int _totalVentasDocs = 0;
  double _ventasMes = 0;
  double _comprasMes = 0;
  double _valorStock = 0;
  ResumenCuentasCobrar? _resumenCc;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    _cargar();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final productos = await _productoService.obtenerTodos();
    final clientes = await _clienteService.obtenerTodos();
    final docsVenta =
        await AnalyticsService.instance.cantidadDocumentosVenta();
    final ahora = DateTime.now();
    final inicioMes = DateTime(ahora.year, ahora.month, 1);
    final ventasMes =
        await _remitoService.totalVentasPorPeriodo(inicioMes, ahora);
    final comprasMes =
        await _compraService.totalComprasPorPeriodo(inicioMes, ahora);
    final resumenCc = await _ccService.resumenDashboard();

    if (!mounted) return;
    setState(() {
      _totalProductos = productos.length;
      _stockTotal = productos.fold(0, (s, p) => s + p.stock);
      _sinStock = productos.where((p) => p.stock == 0).length;
      _conStock = productos.where((p) => p.stock > 0).length;
      _valorStock = productos.fold(0.0, (s, p) => s + p.precio * p.stock);
      _totalClientes = clientes.length;
      _totalVentasDocs = docsVenta;
      _ventasMes = ventasMes;
      _comprasMes = comprasMes;
      _resumenCc = resumenCc;
      _cargando = false;
    });
  }

  static String _fmt(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final userName =
        AuthService.instance.currentUser?.nombre ?? 'Usuario';
    final cs = Theme.of(context).colorScheme;
    final ahora = DateTime.now();
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final fecha =
        '${ahora.day} de ${meses[ahora.month - 1]} de ${ahora.year}';

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Inicio',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      backgroundColor: cs.surface,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Encabezado de bienvenida ─────────────────────────────
                    Row(
                      children: [
                        MediaAvatar(
                          path: branding.logoUiPath.isNotEmpty
                              ? branding.logoUiPath
                              : branding.imagenUiPath,
                          radius: 24,
                          fallbackLetter: branding.nombre.isNotEmpty
                              ? branding.nombre[0]
                              : 'T',
                          backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branding.nombre,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Bienvenido, $userName',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                fecha,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // ── Calculadora rápida ───────────────────────────────────
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            Icons.calculate_rounded,
                            color: cs.primary,
                          ),
                        ),
                        title: const Text(
                          'Calculadora',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Sumas, restos, %, cambio rápido en mostrador',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CalculadoraPage(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── KPI Cards ────────────────────────────────────────────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth < 500 ? 2 : 4;
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: cols == 2 ? 1.8 : 2.2,
                          children: [
                            _KpiCard(
                              title: 'Productos',
                              value: _fmt(_totalProductos),
                              icon: Icons.inventory_2_rounded,
                              color: const Color(0xFF8B5CF6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProductosPage(),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Stock total',
                              value: _fmt(_stockTotal),
                              icon: Icons.layers_rounded,
                              color: const Color(0xFF22C55E),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProductosPage(
                                      soloConStockInicial: true,
                                    ),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Valor stock',
                              value: '\$${_fmt(_valorStock)}',
                              icon: Icons.attach_money_rounded,
                              color: const Color(0xFF3B82F6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProductosPage(
                                      ordenarPorValorStockInicial: true,
                                    ),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Sin stock',
                              value: _fmt(_sinStock),
                              icon: Icons.warning_amber_rounded,
                              color: const Color(0xFFEF4444),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProductosPage(
                                      soloSinStockInicial: true,
                                    ),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Con stock',
                              value: _fmt(_conStock),
                              icon: Icons.check_circle_outline_rounded,
                              color: const Color(0xFF10B981),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProductosPage(
                                      soloConStockInicial: true,
                                    ),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Clientes',
                              value: _fmt(_totalClientes),
                              icon: Icons.groups_rounded,
                              color: const Color(0xFF0891B2),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ClientesPage(),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Ventas totales',
                              value: _fmt(_totalVentasDocs),
                              icon: Icons.receipt_long_rounded,
                              color: const Color(0xFFF59E0B),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const VentasTotalesPage(),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Ventas del mes',
                              value: '\$${_fmt(_ventasMes)}',
                              icon: Icons.payments_rounded,
                              color: const Color(0xFF16A34A),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const VentasPage(),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                            _KpiCard(
                              title: 'Compras del mes',
                              value: '\$${_fmt(_comprasMes)}',
                              icon: Icons.shopping_cart_rounded,
                              color: const Color(0xFF7C3AED),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ComprasPage(),
                                  ),
                                ).then((_) => _cargar());
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    if (_resumenCc != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ClientesDeudoresPage(),
                              ),
                            ).then((_) => _cargar());
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cuentas por cobrar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '\$${_fmt(_resumenCc!.montoTotalPendiente)}',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: cs.error,
                                  ),
                                ),
                                Text('${_resumenCc!.clientesConDeuda} clientes'),
                                Text(
                                  '${_resumenCc!.ventasPendientes} ventas pendientes',
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Ver detalle →',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
