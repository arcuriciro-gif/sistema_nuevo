import 'dart:io';

import 'package:flutter/material.dart';

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
import 'productos_page.dart';

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
  ResumenCuentasCobrar? _resumenCc;
  List<Producto> _ultimosProductos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
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
      _totalClientes = clientes.length;
      _totalRemitos = remitos;
      _ventasMes = ventasMes;
      _comprasMes = comprasMes;
      _resumenCc = resumenCc;
      _ultimosProductos = sorted.take(5).toList();
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
                            ),
                            _KpiCard(
                              title: 'Stock total',
                              value: _fmt(_stockTotal),
                              icon: Icons.layers_rounded,
                              color: const Color(0xFF22C55E),
                            ),
                            _KpiCard(
                              title: 'Valor stock',
                              value: '\$${_fmt(_valorStock)}',
                              icon: Icons.attach_money_rounded,
                              color: const Color(0xFF3B82F6),
                            ),
                            _KpiCard(
                              title: 'Sin stock',
                              value: _fmt(_sinStock),
                              icon: Icons.warning_amber_rounded,
                              color: const Color(0xFFEF4444),
                              onTap: _sinStock == 0
                                  ? null
                                  : () {
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
                              title: 'Clientes',
                              value: _fmt(_totalClientes),
                              icon: Icons.groups_rounded,
                              color: const Color(0xFF0891B2),
                            ),
                            _KpiCard(
                              title: 'Remitos totales',
                              value: _fmt(_totalRemitos),
                              icon: Icons.description_rounded,
                              color: const Color(0xFFF59E0B),
                            ),
                            _KpiCard(
                              title: 'Ventas del mes',
                              value: '\$${_fmt(_ventasMes)}',
                              icon: Icons.payments_rounded,
                              color: const Color(0xFF16A34A),
                            ),
                            _KpiCard(
                              title: 'Compras del mes',
                              value: '\$${_fmt(_comprasMes)}',
                              icon: Icons.shopping_cart_rounded,
                              color: const Color(0xFF7C3AED),
                            ),
                          ],
                        );
                      },
                    ),
                    if (_resumenCc != null) ...[
                      const SizedBox(height: 16),
                      Card(
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
                                child: TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ClientesDeudoresPage(),
                                      ),
                                    ).then((_) => _cargar());
                                  },
                                  icon: const Icon(Icons.visibility_rounded),
                                  label: const Text('Ver detalle'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // ── Últimos productos ────────────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Últimos productos cargados',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_ultimosProductos.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'No hay productos registrados',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              )
                            else
                              ...(_ultimosProductos.map(
                                (p) => ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: cs.primaryContainer,
                                    child: Text(
                                      p.codigo.isNotEmpty
                                          ? p.codigo[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  title: Text(p.descripcion),
                                  subtitle: Text('${p.codigo} · ${p.marca}'),
                                  trailing: Text(
                                    '\$${_fmt(p.precio)}',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
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
