import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/proveedor.dart';
import '../services/excel_service.dart';
import '../services/pedido_service.dart';
import '../services/pdf_service.dart';
import '../services/proveedor_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import 'pedido_form_page.dart';

/// Planilla de pedidos a proveedores, agrupada por proveedor.
class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  final _service = PedidoService();
  final _proveedorService = ProveedorService();
  final _pdfService = PdfService();
  final _excelService = ExcelService();

  List<Map<String, dynamic>> _pedidos = [];
  List<Proveedor> _proveedores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatos);
    _iniciar();
  }

  void _onDatos() {
    if (mounted) _cargar(silent: true);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatos);
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _service.asegurarProveedoresPlanilla();
    await _cargar();
  }

  Future<void> _cargar({bool silent = false}) async {
    if (!silent && mounted) setState(() => _cargando = true);
    final pedidos = await _service.obtenerTodosConConteo();
    final proveedores = await _proveedorService.obtenerTodos();
    if (!mounted) return;
    setState(() {
      _pedidos = pedidos;
      _proveedores = proveedores;
      _cargando = false;
    });
  }

  Map<String, List<Map<String, dynamic>>> get _porProveedor {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final nombre in PedidoService.proveedoresPlanilla) {
      map[nombre] = [];
    }
    for (final p in _pedidos) {
      final nombre = (p['proveedorNombre'] ?? 'Sin proveedor').toString();
      map.putIfAbsent(nombre, () => []).add(p);
    }
    // Quitar grupos vacíos que no son de la planilla (salvo que tengan pedidos).
    map.removeWhere(
      (k, v) =>
          v.isEmpty && !PedidoService.proveedoresPlanilla.contains(k),
    );
    return map;
  }

  Future<void> _nuevoPedido({Proveedor? proveedor}) async {
    Proveedor? elegido = proveedor;
    if (elegido == null) {
      elegido = await _elegirProveedor();
      if (elegido == null) return;
    }

    if (elegido.id != null) {
      final borrador = await _service.borradorDelDia(elegido.id!);
      if (borrador != null && mounted) {
        final abrir = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Pedido del día'),
            content: Text(
              'Ya hay un borrador de hoy para ${elegido!.nombre} '
              '(${borrador.numero}). ¿Abrirlo?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Crear otro'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abrir'),
              ),
            ],
          ),
        );
        if (abrir == true) {
          await _abrirForm(pedidoId: borrador.id);
          return;
        }
      }
    }

    await _abrirForm(proveedor: elegido);
  }

  Future<Proveedor?> _elegirProveedor() async {
    if (_proveedores.isEmpty) return null;
    return showModalBottomSheet<Proveedor>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('Elegir proveedor'),
              subtitle: Text('Los pedidos se agrupan automáticamente'),
            ),
            ..._proveedores.map(
              (p) => ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(p.nombre),
                onTap: () => Navigator.pop(ctx, p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirForm({int? pedidoId, Proveedor? proveedor}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoFormPage(
          pedidoId: pedidoId,
          proveedorInicial: proveedor,
        ),
      ),
    );
    if (mounted) _cargar(silent: true);
  }

  Future<void> _exportarPedido(
    Map<String, dynamic> row, {
    required String formato,
  }) async {
    final id = row['id'] as int?;
    if (id == null) return;
    final pedido = await _service.obtenerPorId(id);
    final items = await _service.obtenerItems(id);
    if (pedido == null || !mounted) return;

    final headers = ['Artículo', 'Cantidad', 'Color', 'Observaciones'];
    final filasStr = items
        .map(
          (i) => [
            i.articulo,
            '${i.cantidad}',
            i.color,
            i.observaciones,
          ],
        )
        .toList();
    final filasDyn = items
        .map(
          (i) => [
            i.articulo,
            i.cantidad,
            i.color,
            i.observaciones,
          ],
        )
        .toList();
    final titulo =
        'Pedido ${pedido.numero} — ${pedido.proveedorNombre}';

    try {
      if (formato == 'pdf' || formato == 'print') {
        final bytes = await _pdfService.generateListPdf(
          titulo: titulo,
          headers: headers,
          filas: filasStr,
        );
        if (formato == 'print') {
          await Printing.layoutPdf(onLayout: (_) async => bytes);
        } else {
          final file = await _pdfService.guardarPdfReporte(
            bytes,
            'pedido_${pedido.numero}.pdf',
          );
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)], text: titulo),
          );
        }
      } else {
        final file = await _excelService.exportarLibro(
          nombreHoja: 'Pedido',
          nombreArchivo: 'pedido_${pedido.numero}.xlsx',
          headers: headers,
          filas: filasDyn,
        );
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: titulo),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $e')),
      );
    }
  }

  Future<void> _menuPedido(Map<String, dynamic> row) async {
    final id = row['id'] as int?;
    if (id == null) return;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Editar'),
              onTap: () => Navigator.pop(ctx, 'editar'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('Exportar PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded),
              title: const Text('Exportar Excel'),
              onTap: () => Navigator.pop(ctx, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.print_rounded),
              title: const Text('Imprimir'),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppVisuals.danger(Theme.of(ctx).colorScheme)),
              title: Text(
                'Eliminar',
                style: TextStyle(color: AppVisuals.danger(Theme.of(ctx).colorScheme)),
              ),
              onTap: () => Navigator.pop(ctx, 'eliminar'),
            ),
          ],
        ),
      ),
    );
    if (accion == null || !mounted) return;
    if (accion == 'editar') {
      await _abrirForm(pedidoId: id);
      return;
    }
    if (accion == 'pdf') {
      await _exportarPedido(row, formato: 'pdf');
      return;
    }
    if (accion == 'excel') {
      await _exportarPedido(row, formato: 'excel');
      return;
    }
    if (accion == 'print') {
      await _exportarPedido(row, formato: 'print');
      return;
    }
    if (accion == 'eliminar') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eliminar pedido'),
          content: Text('¿Eliminar ${row['numero']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _service.eliminar(id);
        await _cargar(silent: true);
      }
    }
  }

  String _fmtFecha(dynamic raw) {
    final f = DateTime.tryParse(raw?.toString() ?? '');
    if (f == null) return '-';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/'
        '${f.year}';
  }

  Color _colorEstado(String estado, ColorScheme cs) {
    switch (estado) {
      case 'enviado':
        return const Color(0xFF2563EB);
      case 'cerrado':
        return cs.outline;
      default:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grupos = _porProveedor;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Pedidos',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevoPedido(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo pedido'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [
                  Text(
                    'Planilla por proveedor. Podés editar el pedido todo el día.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ...grupos.entries.map((entry) {
                    final proveedor = _proveedores.cast<Proveedor?>().firstWhere(
                          (p) => p?.nombre == entry.key,
                          orElse: () => null,
                        );
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        initiallyExpanded: entry.value.isNotEmpty ||
                            PedidoService.proveedoresPlanilla.contains(entry.key),
                        leading: const Icon(Icons.local_shipping_rounded),
                        title: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          entry.value.isEmpty
                              ? 'Sin pedidos'
                              : '${entry.value.length} pedido(s)',
                        ),
                        trailing: IconButton(
                          tooltip: 'Nuevo para ${entry.key}',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _nuevoPedido(
                            proveedor: proveedor ??
                                Proveedor(
                                  nombre: entry.key,
                                  telefono: '',
                                  email: '',
                                  observaciones: '',
                                ),
                          ),
                        ),
                        children: entry.value.isEmpty
                            ? [
                                ListTile(
                                  title: Text(
                                    'Todavía no hay pedidos',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () => _nuevoPedido(
                                      proveedor: proveedor,
                                    ),
                                    child: const Text('Crear'),
                                  ),
                                ),
                              ]
                            : entry.value.map((row) {
                                final estado =
                                    (row['estado'] ?? 'borrador').toString();
                                return ListTile(
                                  title: Text('${row['numero']}'),
                                  subtitle: Text(
                                    '${_fmtFecha(row['fecha'])} · '
                                    '${row['itemsCount']} ítems · '
                                    '${row['cantidadTotal']} u.',
                                  ),
                                  trailing: Chip(
                                    label: Text(estado),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(
                                      color: _colorEstado(estado, cs),
                                    ),
                                    labelStyle: TextStyle(
                                      color: _colorEstado(estado, cs),
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () =>
                                      _abrirForm(pedidoId: row['id'] as int?),
                                  onLongPress: () => _menuPedido(row),
                                );
                              }).toList(),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
