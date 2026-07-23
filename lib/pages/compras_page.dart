import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../models/chat_mensaje.dart';
import '../services/compra_service.dart';
import '../theme/app_visuals.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'compra_form_page.dart';
import 'proveedores_page.dart';
import '../theme/module_app_bar.dart';

class ComprasPage extends StatefulWidget {
  const ComprasPage({super.key});

  @override
  State<ComprasPage> createState() => _ComprasPageState();
}

class _ComprasPageState extends State<ComprasPage> {
  final CompraService service = CompraService();
  final TextEditingController buscarController = TextEditingController();

  List<Map<String, dynamic>> compras = [];
  List<Map<String, dynamic>> comprasOriginales = [];
  bool cargando = true;
  DateTime? _desde;
  DateTime? _hasta;
  double _totalPeriodo = 0;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosRemotos);
    cargar();
  }

  void _onDatosRemotos() {
    if (!mounted) return;
    cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosRemotos);
    buscarController.dispose();
    super.dispose();
  }

  String _fmtDia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  Future<void> cargar() async {
    setState(() => cargando = true);
    if (_desde != null && _hasta != null) {
      comprasOriginales = await service.obtenerPorPeriodo(_desde!, _hasta!);
      _totalPeriodo =
          await service.totalComprasPorPeriodo(_desde!, _hasta!);
    } else {
      comprasOriginales = await service.obtenerTodasConProveedor();
      _totalPeriodo = comprasOriginales.fold<double>(
        0,
        (s, c) => s + ((c['total'] as num?)?.toDouble() ?? 0),
      );
    }
    _filtrar(buscarController.text, actualizarEstado: false);
    if (!mounted) return;
    setState(() => cargando = false);
  }

  Future<void> _elegirPeriodo() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 5),
      lastDate: DateTime(ahora.year + 1),
      initialDateRange: _desde != null && _hasta != null
          ? DateTimeRange(start: _desde!, end: _hasta!)
          : DateTimeRange(
              start: ahora.subtract(const Duration(days: 7)),
              end: ahora,
            ),
      helpText: 'Compras entre fechas',
      saveText: 'Aplicar',
    );
    if (rango == null) return;
    setState(() {
      _desde = DateTime(rango.start.year, rango.start.month, rango.start.day);
      _hasta = DateTime(rango.end.year, rango.end.month, rango.end.day);
    });
    await cargar();
  }

  void _limpiarPeriodo() {
    setState(() {
      _desde = null;
      _hasta = null;
    });
    cargar();
  }

  void _filtrar(String texto, {bool actualizarEstado = true}) {
    final filtro = texto.toLowerCase().trim();
    compras = comprasOriginales.where((c) {
      final numero = (c['numero'] ?? '').toString().toLowerCase();
      final proveedor = (c['proveedorNombre'] ??
              c['proveedorNombreActual'] ??
              '')
          .toString()
          .toLowerCase();
      return numero.contains(filtro) || proveedor.contains(filtro);
    }).toList();

    if (actualizarEstado && mounted) {
      setState(() {});
    }
  }

  String formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Future<void> verItems(Map<String, dynamic> compra) async {
    final items = await service.obtenerItems(compra['id']);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_cart_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Compra ${compra['numero']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Sin ítems'))
                  : ListView.builder(
                      controller: ctrl,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return ListTile(
                          title: Text(item['productoDescripcion'] ?? ''),
                          subtitle: Text(
                            'Código: ${item['codigo'] ?? '-'}  |  Costo: \$${((item['costo'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('x${item['cantidad']}'),
                              Text(
                                '\$${((item['subtotal'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '\$${((compra['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> confirmarAnular(Map<String, dynamic> compra) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular compra'),
        content: Text(
          '¿Anular la compra ${compra['numero']}? Se descontará el stock ingresado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Anular',
              style: TextStyle(
                color: AppVisuals.danger(Theme.of(context).colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.anular(compra['id']);
      await cargar();
    }
  }

  Future<void> confirmarEliminar(Map<String, dynamic> compra) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar compra'),
        content: Text(
          '¿Eliminar la compra ${compra['numero']}? '
          'Si estaba activa se revierte el stock y se borra del historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Eliminar',
              style: TextStyle(
                color: AppVisuals.danger(Theme.of(context).colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await service.eliminar((compra['id'] as num).toInt());
        await cargar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('No autorizado')
                  ? 'No tenés permiso para eliminar'
                  : 'No se pudo eliminar: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editar(Map<String, dynamic> compra) async {
    final id = (compra['id'] as num?)?.toInt();
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompraFormPage(compraId: id)),
    );
    await cargar();
  }

  bool get _puedeEditar => AuthorizationService.instance.puede(
        AuthModules.compras,
        AuthzAction.editar,
      );

  bool get _puedeAnular => AuthorizationService.instance.puede(
        AuthModules.compras,
        AuthzAction.anular,
      );

  bool get _puedeEliminar =>
      AuthorizationService.instance.puede(
        AuthModules.compras,
        AuthzAction.eliminar,
      ) ||
      _puedeAnular;

  Color colorEstado(String estado) {
    final colorScheme = Theme.of(context).colorScheme;
    return estado == 'anulada'
        ? AppVisuals.danger(colorScheme)
        : AppVisuals.success(colorScheme);
  }

  Widget estadoChip(String estado) {
    final color = colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Compras',
        actions: [
          IconButton(
            tooltip: 'Proveedores',
            icon: const Icon(Icons.local_shipping_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProveedoresPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargar,
          ),
        ],
      ),
      floatingActionButton: AuthorizationService.instance.puede(
              AuthModules.compras, AuthzAction.crear)
          ? FloatingActionButton.extended(
              heroTag: 'fab_compras',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva compra'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CompraFormPage()),
                );
                cargar();
              },
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _elegirPeriodo,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      _desde != null && _hasta != null
                          ? '${_fmtDia(_desde!)} → ${_fmtDia(_hasta!)}'
                          : 'Filtrar por fechas',
                    ),
                  ),
                ),
                if (_desde != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Quitar filtro de fechas',
                    onPressed: _limpiarPeriodo,
                    icon: const Icon(Icons.clear_rounded),
                  ),
                ],
              ],
            ),
          ),
          if (_desde != null && _hasta != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Total del período: \$${_totalPeriodo.toStringAsFixed(2)} '
                  '(${comprasOriginales.length} compras)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: buscarController,
              onChanged: _filtrar,
              decoration: InputDecoration(
                hintText: 'Buscar compra o proveedor...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : compras.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay compras registradas.',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        itemCount: compras.length,
                        itemBuilder: (context, i) {
                          final compra = compras[i];
                          final estado =
                              (compra['estado'] ?? 'confirmada').toString();
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => verItems(compra),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: colorEstado(estado)
                                              .withValues(alpha: .15),
                                          child: Icon(
                                            Icons.shopping_cart_rounded,
                                            color: colorEstado(estado),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                compra['numero'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                compra['proveedorNombre'] ??
                                                    'Sin proveedor',
                                              ),
                                              Text(
                                                formatearFecha(
                                                  compra['fecha']?.toString(),
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${((compra['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            estadoChip(estado),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (estado != 'anulada' ||
                                        _puedeEliminar) ...[
                                      const Divider(height: 20),
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 4,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () =>
                                                showComentariosInternos(
                                              context,
                                              entidadTipo: 'compra',
                                              entidadId: '${compra['id']}',
                                              titulo:
                                                  'Compra ${compra['numero'] ?? compra['id']}',
                                            ),
                                            icon: const Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('Notas'),
                                          ),
                                          TextButton.icon(
                                            onPressed: () =>
                                                showCompartirEnChatDialog(
                                              context,
                                              compartido: ChatCompartido(
                                                tipo: 'compra',
                                                idRef: '${compra['id']}',
                                                titulo:
                                                    'Compra ${compra['numero'] ?? compra['id']}',
                                                subtitulo:
                                                    '${compra['proveedorNombre'] ?? 'Sin proveedor'} · '
                                                    '\$${((compra['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                                datos: {
                                                  'proveedor':
                                                      compra['proveedorNombre'],
                                                  'total': compra['total'],
                                                  'estado': compra['estado'],
                                                },
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.forum_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('Compartir'),
                                          ),
                                          if (estado != 'anulada' &&
                                              _puedeEditar)
                                            TextButton.icon(
                                              onPressed: () => _editar(compra),
                                              icon: const Icon(
                                                Icons.edit_rounded,
                                                size: 18,
                                              ),
                                              label: const Text('Editar'),
                                            ),
                                          if (estado != 'anulada' &&
                                              _puedeAnular)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  confirmarAnular(compra),
                                              icon: const Icon(
                                                Icons.block_rounded,
                                                size: 18,
                                              ),
                                              label: const Text('Anular'),
                                            ),
                                          if (_puedeEliminar)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  confirmarEliminar(compra),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                              ),
                                              label: const Text('Eliminar'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: AppVisuals
                                                    .danger(
                                                  Theme.of(context)
                                                      .colorScheme,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
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
