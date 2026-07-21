import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/chat_mensaje.dart';
import '../models/venta.dart';
import '../services/venta_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cobrar_dialog.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'venta_factura_page.dart';

class VentasPage extends StatefulWidget {
  final String titulo;
  /// Tipos disponibles en este módulo. Si es null, usa facturas A/B/C.
  final Map<String, String>? tipos;

  const VentasPage({
    super.key,
    this.titulo = 'Ventas',
    this.tipos,
  });

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> {
  final VentaService _service = VentaService();
  final TextEditingController _buscarCtrl = TextEditingController();

  List<Venta> _todas = [];
  List<Venta> _filtradas = [];
  String _tipoFiltro = 'todos';
  bool _cargando = true;

  Map<String, String> get _tipos =>
      widget.tipos ??
      const {
        'factura_a': 'Factura A',
        'factura_b': 'Factura B',
        'factura_c': 'Factura C',
      };

  Map<String, String> get _tiposFiltro => {
        'todos': 'Todos',
        ..._tipos,
      };

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
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final todas = await _service.obtenerTodas();
    final permitidos = _tipos.keys.toSet();
    _todas = todas.where((v) => permitidos.contains(v.tipo)).toList();
    _aplicarFiltro();
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  void _aplicarFiltro() {
    final q = _buscarCtrl.text.toLowerCase();
    _filtradas = _todas.where((v) {
      final tipoOk = _tipoFiltro == 'todos' || v.tipo == _tipoFiltro;
      final textoOk = q.isEmpty ||
          v.numero.toLowerCase().contains(q) ||
          (v.clienteNombre?.toLowerCase().contains(q) ?? false);
      return tipoOk && textoOk;
    }).toList();
    setState(() {});
  }

  Future<void> _nuevaVenta(String tipo) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => VentaFacturaPage(tipo: tipo)),
    );
    await _cargar();
  }

  Future<void> _verDetalle(Venta venta) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VentaFacturaPage(tipo: venta.tipo, ventaId: venta.id),
      ),
    );
    await _cargar();
  }

  Color _colorTipo(String tipo, ColorScheme cs) {
    switch (tipo) {
      case 'factura_a':
        return AppVisuals.danger(cs);
      case 'factura_b':
        return AppVisuals.info(cs);
      case 'factura_c':
        return AppVisuals.success(cs);
      case 'presupuesto':
        return AppVisuals.warning(cs);
      case 'nota_entrega':
        return AppVisuals.info(cs);
      case 'comprobante_interno':
        return AppVisuals.neutral(cs);
      default:
        return AppVisuals.neutral(cs);
    }
  }

  Color _colorEstadoPago(String estado, ColorScheme cs) =>
      colorEstadoPago(estado, cs);

  String _formatFecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/'
      '${fecha.year}';

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'presupuesto':
        return Icons.request_quote_rounded;
      case 'nota_entrega':
        return Icons.local_shipping_outlined;
      case 'comprobante_interno':
        return Icons.article_outlined;
      case 'factura_a':
        return Icons.looks_one_rounded;
      case 'factura_b':
        return Icons.looks_two_rounded;
      case 'factura_c':
        return Icons.looks_3_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unSoloTipo = _tipos.length == 1;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: widget.titulo,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_${widget.titulo}',
        onPressed: () {
          if (unSoloTipo) {
            _nuevaVenta(_tipos.keys.first);
          } else {
            _mostrarMenuNueva();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscarCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por número o cliente...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _aplicarFiltro(),
                  ),
                ),
                if (_tipos.length > 1) ...[
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _tipoFiltro,
                    items: _tiposFiltro.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      _tipoFiltro = v;
                      _aplicarFiltro();
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _filtradas.isEmpty
                    ? Center(
                        child: Text(
                          'No hay documentos para mostrar',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          8,
                          8,
                          8,
                          8 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: _filtradas.length,
                        itemBuilder: (context, i) {
                          final v = _filtradas[i];
                          final colorTipo = _colorTipo(v.tipo, cs);
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorTipo.withValues(alpha: .15),
                                child: Icon(
                                  _iconoTipo(v.tipo),
                                  color: colorTipo,
                                ),
                              ),
                              title: Text(
                                '${v.tipoLabel}  ${v.numero}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${v.clienteNombre ?? 'Consumidor final'} · '
                                '${_formatFecha(v.fecha)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Comentarios internos',
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                    ),
                                    onPressed: () => showComentariosInternos(
                                      context,
                                      entidadTipo: v.tipo == 'presupuesto'
                                          ? 'presupuesto'
                                          : 'venta',
                                      entidadId: '${v.id}',
                                      titulo: '${v.tipoLabel} ${v.numero}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Compartir en chat',
                                    icon: const Icon(Icons.forum_rounded),
                                    onPressed: () => showCompartirEnChatDialog(
                                      context,
                                      compartido: ChatCompartido(
                                        tipo: v.tipo == 'presupuesto'
                                            ? 'presupuesto'
                                            : 'venta',
                                        idRef: '${v.id}',
                                        titulo: '${v.tipoLabel} ${v.numero}',
                                        subtitulo:
                                            '${v.clienteNombre ?? 'Consumidor final'} · '
                                            '\$${v.total.toStringAsFixed(2)} · '
                                            '${v.estadoPagoLabel}'
                                            '${v.saldoPendiente > 0.009 ? ' · Saldo \$${v.saldoPendiente.toStringAsFixed(2)}' : ''}',
                                        datos: {
                                          'cliente': v.clienteNombre,
                                          'total': v.total,
                                          'estadoPago': v.estadoPago,
                                          'saldoPendiente': v.saldoPendiente,
                                          'tipo': v.tipo,
                                        },
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '\$${v.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        v.estadoPagoLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _colorEstadoPago(v.estadoPago, cs),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => _verDetalle(v),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _mostrarMenuNueva() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Nuevo ${widget.titulo.toLowerCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ..._tipos.entries.map(
              (e) => ListTile(
                leading: CircleAvatar(child: Icon(_iconoTipo(e.key))),
                title: Text(e.value),
                onTap: () {
                  Navigator.pop(context);
                  _nuevaVenta(e.key);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
