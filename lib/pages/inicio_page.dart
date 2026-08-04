import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/inventory/stock_kpi.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/compra_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/erp/erp_kpi_tile.dart';
import '../widgets/erp/erp_quick_action_bar.dart';
import '../widgets/erp/erp_section_header.dart';

/// Centro de Operaciones: info útil para empezar el día (sin gráficos grandes).
class InicioPage extends StatefulWidget {
  const InicioPage({
    super.key,
    this.onIrA,
    this.onBuscar,
    this.onEscanear,
  });

  final void Function(String tituloModulo)? onIrA;
  final VoidCallback? onBuscar;
  final VoidCallback? onEscanear;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  final _productoService = ProductoService();
  final _remitoService = RemitoService();
  final _compraService = CompraService();
  final _ccService = CuentaCorrienteService();

  double _ventasDia = 0;
  double _ventasMes = 0;
  double _gananciaDia = 0;
  int _sinStock = 0;
  int _criticos = 0;
  int _clientesDeuda = 0;
  double _deudaTotal = 0;
  List<Map<String, dynamic>> _ultimosDocs = [];
  List<Map<String, dynamic>> _actividad = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatos);
    _cargar();
  }

  void _onDatos() {
    if (mounted) _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatos);
    super.dispose();
  }

  Future<void> _cargar() async {
    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final inicioMes = DateTime(ahora.year, ahora.month, 1);

    final productos = await _productoService.obtenerTodos();
    final ventasDia = await AnalyticsService.instance.ventasTotales(
      desde: inicioDia,
      hasta: ahora,
    );
    final ventasMes = await AnalyticsService.instance.ventasTotales(
      desde: inicioMes,
      hasta: ahora,
    );
    final gananciaDia = await AnalyticsService.instance.gananciaReal(
      desde: inicioDia,
      hasta: ahora,
    );
    final resumenCc = await _ccService.resumenDashboard();
    final docs = await AnalyticsService.instance.listarDocumentosVenta();
    final compras = await _compraService.obtenerTodasConProveedor();

    final sinStock = productos.where((p) => StockKpi.sinStock(p.stock)).length;
    final criticos =
        productos.where((p) => StockKpi.conStock(p.stock) && p.stock <= 5).length;

    final actividad = <Map<String, dynamic>>[];
    for (final d in docs.take(8)) {
      actividad.add({
        'tipo': 'venta',
        'titulo': 'Venta ${d['numero'] ?? ''}',
        'detalle': d['clienteNombre'] ?? d['tipo'] ?? '',
        'cuando': d['fecha'] ?? d['fechaCreacion'],
        'monto': d['total'],
      });
    }
    for (final c in compras.take(5)) {
      actividad.add({
        'tipo': 'compra',
        'titulo': 'Compra ${c['numero'] ?? ''}',
        'detalle': c['proveedorNombreActual'] ?? 'Proveedor',
        'cuando': c['fecha'] ?? c['fechaCreacion'],
        'monto': c['total'],
      });
    }
    actividad.sort((a, b) {
      final da = DateTime.tryParse('${a['cuando']}') ?? DateTime(1970);
      final db = DateTime.tryParse('${b['cuando']}') ?? DateTime(1970);
      return db.compareTo(da);
    });

    // Remitos recientes también en “últimos movimientos”.
    final remitos = await _remitoService.obtenerTodosConCliente();

    if (!mounted) return;
    setState(() {
      _ventasDia = ventasDia;
      _ventasMes = ventasMes;
      _gananciaDia = gananciaDia;
      _sinStock = sinStock;
      _criticos = criticos;
      _clientesDeuda = resumenCc.clientesConDeuda;
      _deudaTotal = resumenCc.montoTotalPendiente;
      _ultimosDocs = docs.take(6).toList();
      _actividad = [
        ...actividad.take(10),
        ...remitos.take(3).map(
              (r) => {
                'tipo': 'remito',
                'titulo': 'Comprobante ${r['numero'] ?? ''}',
                'detalle': r['clienteNombre'] ?? '',
                'cuando': r['fecha'] ?? r['fechaCreacion'],
                'monto': r['total'],
              },
            ),
      ];
      _cargando = false;
    });
  }

  static String _money(num v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$${buf.toString()}';
  }

  void _go(String title) => widget.onIrA?.call(title);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = AuthService.instance.currentUser?.nombre ?? 'Usuario';
    final marca = BrandingService.instance.nombre;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Centro de operaciones'),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hola, $user',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '$marca · listo para vender',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ErpQuickActionBar(
                    actions: [
                      ErpQuickAction(
                        label: 'Nueva venta',
                        icon: Icons.point_of_sale_rounded,
                        onTap: () => _go('Venta Rápida'),
                      ),
                      ErpQuickAction(
                        label: 'Producto',
                        icon: Icons.add_box_outlined,
                        onTap: () => _go('Productos'),
                      ),
                      ErpQuickAction(
                        label: 'Cliente',
                        icon: Icons.person_add_alt_1_rounded,
                        onTap: () => _go('Clientes'),
                      ),
                      ErpQuickAction(
                        label: 'Comprobante',
                        icon: Icons.description_rounded,
                        onTap: () => _go('Comprobantes'),
                      ),
                      ErpQuickAction(
                        label: 'Compra',
                        icon: Icons.shopping_cart_rounded,
                        onTap: () => _go('Compras'),
                      ),
                      ErpQuickAction(
                        label: 'Buscar',
                        icon: Icons.search_rounded,
                        onTap: widget.onBuscar,
                      ),
                      ErpQuickAction(
                        label: 'Escanear',
                        icon: Icons.qr_code_scanner_rounded,
                        onTap: widget.onEscanear,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ErpSectionHeader(title: 'Hoy'),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 900
                          ? 4
                          : c.maxWidth >= 600
                              ? 2
                              : 2;
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.55,
                        children: [
                          ErpKpiTile(
                            title: 'Ventas del día',
                            value: _money(_ventasDia),
                            icon: Icons.payments_rounded,
                            accent: cs.primary,
                            onTap: () => _go('Comprobantes'),
                          ),
                          ErpKpiTile(
                            title: 'Ganancia estimada',
                            value: _money(_gananciaDia),
                            icon: Icons.trending_up_rounded,
                            accent: Colors.green.shade700,
                            onTap: () => _go('Reportes'),
                          ),
                          ErpKpiTile(
                            title: 'Ventas del mes',
                            value: _money(_ventasMes),
                            icon: Icons.calendar_month_rounded,
                            accent: cs.secondary,
                            onTap: () => _go('Reportes'),
                          ),
                          ErpKpiTile(
                            title: 'Clientes con deuda',
                            value: '$_clientesDeuda',
                            icon: Icons.account_balance_wallet_rounded,
                            accent: Colors.red.shade700,
                            subtitle: _money(_deudaTotal),
                            onTap: () => _go('Cuenta corriente'),
                          ),
                          ErpKpiTile(
                            title: 'Sin stock',
                            value: '$_sinStock',
                            icon: Icons.inventory_2_outlined,
                            accent: Colors.orange.shade800,
                            onTap: () => _go('Stock'),
                          ),
                          ErpKpiTile(
                            title: 'Productos críticos',
                            value: '$_criticos',
                            icon: Icons.warning_amber_rounded,
                            accent: Colors.deepOrange,
                            onTap: () => _go('Productos'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const ErpSectionHeader(title: 'Últimos movimientos'),
                  const SizedBox(height: 8),
                  if (_ultimosDocs.isEmpty)
                    Text(
                      'Sin ventas recientes',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    )
                  else
                    ..._ultimosDocs.map(
                      (d) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.receipt_long_rounded,
                              color: cs.onPrimaryContainer, size: 18),
                        ),
                        title: Text('${d['numero'] ?? 'Doc'}'),
                        subtitle: Text('${d['clienteNombre'] ?? ''}'),
                        trailing: Text(
                          _money((d['total'] as num?) ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () => _go('Comprobantes'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const ErpSectionHeader(title: 'Centro de actividad'),
                  const SizedBox(height: 8),
                  ..._actividad.take(12).map((a) {
                    final icon = switch (a['tipo']) {
                      'compra' => Icons.shopping_cart_outlined,
                      'remito' => Icons.local_shipping_outlined,
                      'sync' => Icons.sync_rounded,
                      _ => Icons.point_of_sale_outlined,
                    };
                    final destino = switch (a['tipo']) {
                      'compra' => 'Compras',
                      'remito' => 'Comprobantes',
                      'venta' => 'Comprobantes',
                      _ => null,
                    };
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      elevation: 0,
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                      child: ListTile(
                        dense: true,
                        leading: Icon(icon, color: cs.primary),
                        title: Text('${a['titulo']}'),
                        subtitle: Text('${a['detalle'] ?? ''}'),
                        trailing: a['monto'] == null
                            ? null
                            : Text(_money((a['monto'] as num?) ?? 0)),
                        onTap: destino == null ? null : () => _go(destino),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

}
