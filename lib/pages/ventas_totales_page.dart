import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../services/analytics_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import 'venta_factura_page.dart';

/// Lista unificada: facturas + remitos + NE/CI, ordenadas por fecha de creación.
class VentasTotalesPage extends StatefulWidget {
  const VentasTotalesPage({super.key});

  @override
  State<VentasTotalesPage> createState() => _VentasTotalesPageState();
}

class _VentasTotalesPageState extends State<VentasTotalesPage> {
  final _buscarCtrl = TextEditingController();
  final _remitoSvc = RemitoService();
  List<Map<String, dynamic>> _todas = [];
  List<Map<String, dynamic>> _filtradas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onRefresh);
    _cargar();
  }

  void _onRefresh() {
    if (!mounted) return;
    _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onRefresh);
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _todas = await AnalyticsService.instance.listarDocumentosVenta();
    _aplicarFiltro(actualizar: false);
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  void _aplicarFiltro({bool actualizar = true}) {
    final q = _buscarCtrl.text.toLowerCase().trim();
    _filtradas = _todas.where((d) {
      if (q.isEmpty) return true;
      final numero = (d['numero'] ?? '').toString().toLowerCase();
      final cliente = (d['clienteNombre'] ?? '').toString().toLowerCase();
      final tipo = (d['tipoLabel'] ?? '').toString().toLowerCase();
      return numero.contains(q) || cliente.contains(q) || tipo.contains(q);
    }).toList();
    if (actualizar && mounted) setState(() {});
  }

  String _fmtFecha(String? raw) {
    final f = DateTime.tryParse(raw ?? '');
    if (f == null) return '-';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/'
        '${f.year}';
  }

  Color _colorTipo(String tipo, ColorScheme cs) {
    switch (tipo) {
      case 'factura_a':
        return AppVisuals.danger(cs);
      case 'factura_b':
        return AppVisuals.info(cs);
      case 'factura_c':
        return AppVisuals.success(cs);
      case 'nota_entrega':
        return AppVisuals.info(cs);
      case 'comprobante_interno':
        return AppVisuals.neutral(cs);
      case 'remito':
        return AppVisuals.warning(cs);
      default:
        return AppVisuals.neutral(cs);
    }
  }

  Future<void> _abrir(Map<String, dynamic> doc) async {
    final origen = doc['origen']?.toString() ?? '';
    if (origen == 'remito') {
      final id = (doc['id'] as num?)?.toInt();
      if (id == null) return;
      final items = await _remitoSvc.obtenerItems(id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remito ${doc['numero']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${doc['clienteNombre'] ?? 'Sin cliente'} · '
                    '${_fmtFecha(doc['fecha']?.toString())}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  ...items.map((it) {
                    final cant = (it['cantidad'] as num?)?.toInt() ?? 0;
                    final precio = (it['precio'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        it['descripcion']?.toString() ??
                            'Producto ${it['productoId']}',
                      ),
                      subtitle: Text('$cant × \$${precio.toStringAsFixed(2)}'),
                      trailing: Text(
                        '\$${((it['subtotal'] as num?)?.toDouble() ?? cant * precio).toStringAsFixed(2)}',
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: \$${((doc['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    final tipo = doc['tipo']?.toString() ?? 'factura_b';
    final id = (doc['id'] as num?)?.toInt();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VentaFacturaPage(tipo: tipo, ventaId: id),
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Ventas totales'),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _buscarCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar por número, cliente o tipo…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: (_) => _aplicarFiltro(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_filtradas.length} documento'
                      '${_filtradas.length == 1 ? '' : 's'}'
                      ' (facturas, remitos y más)',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filtradas.isEmpty
                      ? Center(
                          child: Text(
                            'Sin ventas registradas',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            0,
                            10,
                            16 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          itemCount: _filtradas.length,
                          itemBuilder: (context, i) {
                            final d = _filtradas[i];
                            final tipo = d['tipo']?.toString() ?? '';
                            final color = _colorTipo(tipo, cs);
                            final total =
                                (d['total'] as num?)?.toDouble() ?? 0;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                onTap: () => _abrir(d),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      color.withValues(alpha: 0.15),
                                  child: Icon(
                                    tipo == 'remito'
                                        ? Icons.description_rounded
                                        : Icons.receipt_long_rounded,
                                    color: color,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '${d['tipoLabel'] ?? tipo} ${d['numero'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_fmtFecha(d['fecha']?.toString())}'
                                  ' · ${d['clienteNombre'] ?? 'Sin cliente'}'
                                  ' · ${d['estado'] ?? ''}',
                                ),
                                trailing: Text(
                                  '\$${total.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
