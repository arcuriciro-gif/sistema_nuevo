import 'dart:io';

import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/producto.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import 'clientes_deudores_page.dart';
import 'clientes_page.dart';
import 'compras_page.dart';
import 'productos_page.dart';
import 'remitos_page.dart';
import 'stock_page.dart';
import 'ventas_page.dart';

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
  int _totalClientes = 0;
  int _totalRemitos = 0;
  double _ventasMes = 0;
  double _comprasMes = 0;
  double _valorStock = 0;
  double _valorStockCosto = 0;
  ResumenCuentasCobrar? _resumenCc;
  List<Producto> _ultimosProductos = [];
  bool _cargando = true;
  bool _refrescando = false;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    _cargar();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    _cargar(silent: true);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    super.dispose();
  }

  Future<void> _abrir(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) _cargar(silent: true);
  }

  Future<void> _cargar({bool silent = false}) async {
    if (_refrescando) return;
    _refrescando = true;
    if (!silent && mounted) setState(() => _cargando = true);
    try {
      final productos = await _productoService.obtenerTodos();
      final clientes = await _clienteService.obtenerTodos();
      final remitos = await _remitoService.cantidad();
      final ahora = DateTime.now();
      final inicioMes = DateTime(ahora.year, ahora.month, 1);
      final ventasMes =
          await _remitoService.totalVentasPorPeriodo(inicioMes, ahora);
      final comprasMes =
          await _compraService.totalComprasPorPeriodo(inicioMes, ahora);
      final resumenCc = await _ccService.resumenDashboard();

      if (!mounted) return;
      final sorted = [...productos]
        ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
      setState(() {
        _totalProductos = productos.length;
        _stockTotal = productos.fold(0, (s, p) => s + p.stock);
        _sinStock = productos.where((p) => p.stock == 0).length;
        _valorStock = productos.fold(0.0, (s, p) => s + p.precio * p.stock);
        _valorStockCosto =
            productos.fold(0.0, (s, p) => s + p.costo * p.stock);
        _totalClientes = clientes.length;
        _totalRemitos = remitos;
        _ventasMes = ventasMes;
        _comprasMes = comprasMes;
        _resumenCc = resumenCc;
        _ultimosProductos = sorted.take(5).toList();
        _cargando = false;
      });
    } finally {
      _refrescando = false;
    }
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
    final logoPath = branding.imagenUiPath;
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
        showHome: false,
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
                        if (logoPath.isNotEmpty)
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: FileImage(File(logoPath)),
                          )
                        else
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: cs.primaryContainer,
                            child:
                                Icon(Icons.store_rounded, color: cs.primary),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: _cargar,
                          tooltip: 'Actualizar',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // ── KPI Cards ────────────────────────────────────────────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final cols = w < 500
                            ? 2
                            : w < 900
                                ? 3
                                : 4;
                        return GridView.count(
                          crossAxisCount: cols,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: cols >= 4 ? 3.2 : 2.6,
                          children: [
                            _KpiCard(
                              title: 'Productos',
                              value: _fmt(_totalProductos),
                              icon: Icons.inventory_2_rounded,
                              color: const Color(0xFF8B5CF6),
                              onTap: () => _abrir(const ProductosPage()),
                            ),
                            _KpiCard(
                              title: 'Stock total',
                              value: _fmt(_stockTotal),
                              icon: Icons.layers_rounded,
                              color: const Color(0xFF22C55E),
                              onTap: () => _abrir(const StockPage()),
                            ),
                            _KpiCard(
                              title: 'Stock a venta',
                              value: '\$${_fmt(_valorStock)}',
                              icon: Icons.attach_money_rounded,
                              color: const Color(0xFF3B82F6),
                              onTap: () => _abrir(const ProductosPage()),
                            ),
                            _KpiCard(
                              title: 'Stock a costo',
                              value: '\$${_fmt(_valorStockCosto)}',
                              icon: Icons.price_change_rounded,
                              color: const Color(0xFF0EA5E9),
                              onTap: () => _abrir(const ProductosPage()),
                            ),
                            _KpiCard(
                              title: 'Sin stock',
                              value: _fmt(_sinStock),
                              icon: Icons.warning_amber_rounded,
                              color: const Color(0xFFEF4444),
                              onTap: () => _abrir(
                                const ProductosPage(soloSinStockInicial: true),
                              ),
                            ),
                            _KpiCard(
                              title: 'Clientes',
                              value: _fmt(_totalClientes),
                              icon: Icons.groups_rounded,
                              color: const Color(0xFF0891B2),
                              onTap: () => _abrir(const ClientesPage()),
                            ),
                            _KpiCard(
                              title: 'Remitos',
                              value: _fmt(_totalRemitos),
                              icon: Icons.description_rounded,
                              color: const Color(0xFFF59E0B),
                              onTap: () => _abrir(const RemitosPage()),
                            ),
                            _KpiCard(
                              title: 'Ventas del mes',
                              value: '\$${_fmt(_ventasMes)}',
                              icon: Icons.payments_rounded,
                              color: const Color(0xFF16A34A),
                              onTap: () => _abrir(const VentasPage()),
                            ),
                            _KpiCard(
                              title: 'Compras del mes',
                              value: '\$${_fmt(_comprasMes)}',
                              icon: Icons.shopping_cart_rounded,
                              color: const Color(0xFF7C3AED),
                              onTap: () => _abrir(const ComprasPage()),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_resumenCc != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: cs.error,
                            size: 22,
                          ),
                          title: const Text(
                            'Cuentas por cobrar',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${_resumenCc!.clientesConDeuda} clientes · '
                            '${_resumenCc!.ventasPendientes} ventas',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${_fmt(_resumenCc!.montoTotalPendiente)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: cs.error,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ver detalle',
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ClientesDeudoresPage(),
                                    ),
                                  ).then((_) => _cargar());
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // ── Últimos productos ────────────────────────────────────
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Últimos productos cargados',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_ultimosProductos.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'No hay productos registrados',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                            else
                              ...(_ultimosProductos.map(
                                (p) => ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.inventory_2_outlined,
                                    color: cs.primary,
                                    size: 18,
                                  ),
                                  title: Text(
                                    p.descripcion,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${p.codigo} · ${p.marca}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: Text(
                                    '\$${_fmt(p.precio)}',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )),
                          ],
                        ),
                      ),
                    ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
