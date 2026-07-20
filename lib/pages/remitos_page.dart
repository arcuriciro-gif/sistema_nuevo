import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/chat_mensaje.dart';
import '../services/auth_service.dart';
import '../services/documento_cliente_service.dart';
import '../services/pdf_service.dart';
import '../services/permisos_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'remito_form_page.dart';
import '../theme/module_app_bar.dart';

class RemitosPage extends StatefulWidget {
  const RemitosPage({super.key});

  @override
  State<RemitosPage> createState() => _RemitosPageState();
}

class _RemitosPageState extends State<RemitosPage> {
  final RemitoService service = RemitoService();
  final PdfService pdfService = PdfService();
  final TextEditingController buscarController = TextEditingController();

  List<Map<String, dynamic>> remitos = [];
  List<Map<String, dynamic>> remitosOriginales = [];
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
    buscarController.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() => cargando = true);
    try {
      await PermisosService.instance.cargar();
    } catch (_) {}
    remitosOriginales = await service.obtenerTodosConCliente();
    _filtrarRemitos(buscarController.text, actualizarEstado: false);
    if (!mounted) return;
    setState(() => cargando = false);
  }

  void _filtrarRemitos(String texto, {bool actualizarEstado = true}) {
    final filtro = texto.toLowerCase().trim();
    remitos = remitosOriginales.where((remito) {
      final numero = (remito['numero'] ?? '').toString().toLowerCase();
      final cliente =
          (remito['clienteNombre'] ?? '').toString().toLowerCase();
      return numero.contains(filtro) || cliente.contains(filtro);
    }).toList();

    if (actualizarEstado && mounted) {
      setState(() {});
    }
  }

  String formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Future<void> verItems(Map<String, dynamic> remito) async {
    final items = await service.obtenerItems(remito['id']);
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
                    Icons.description_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remito ${remito['numero']}',
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
                          title: Text(item['descripcion'] ?? ''),
                          subtitle: Text(
                            'Código: ${item['codigo']}  |  Marca: ${item['marca'] ?? '-'}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('x${item['cantidad']}'),
                              Text(
                                '\$${(item['subtotal'] as num).toStringAsFixed(2)}',
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '\$${(remito['total'] as num).toStringAsFixed(2)}',
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

  Future<List<dynamic>> _obtenerPdfItems(Map<String, dynamic> remito) {
    return service.obtenerItems(remito['id']);
  }

  Future<void> imprimirRemito(Map<String, dynamic> remito) async {
    final items = await _obtenerPdfItems(remito);
    final pdf = await pdfService.generateRemitoPdf(
      remito,
      items,
      remito['clienteNombre']?.toString() ?? 'Sin cliente',
    );
    if (pdf.isEmpty) return;
    final archivo = await pdfService.guardarPdf(
      pdf,
      'remito_${remito['numero']}.pdf',
    );
    await DocumentoClienteService.instance.archivarPdf(
      archivo: archivo,
      tipo: 'remito',
      numero: remito['numero']?.toString() ?? '',
      clienteNombre: remito['clienteNombre']?.toString() ?? 'Sin cliente',
      clienteId: remito['clienteId'] as int?,
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf);
  }

  Future<void> compartirRemito(Map<String, dynamic> remito) async {
    final items = await _obtenerPdfItems(remito);
    final pdf = await pdfService.generateRemitoPdf(
      remito,
      items,
      remito['clienteNombre']?.toString() ?? 'Sin cliente',
    );
    if (pdf.isEmpty) return;
    final archivo = await pdfService.guardarPdf(
      pdf,
      'remito_${remito['numero']}.pdf',
    );
    await DocumentoClienteService.instance.archivarPdf(
      archivo: archivo,
      tipo: 'remito',
      numero: remito['numero']?.toString() ?? '',
      clienteNombre: remito['clienteNombre']?.toString() ?? 'Sin cliente',
      clienteId: remito['clienteId'] as int?,
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(archivo.path)]),
    );
  }

  Future<void> confirmarAnular(Map<String, dynamic> remito) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular remito'),
        content: Text('¿Anular el remito ${remito['numero']}?'),
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
      await service.anular(remito['id']);
      await cargar();
    }
  }

  bool get _puedeEliminarRemitos {
    final rol = AuthService.instance.currentUser?.rol ?? '';
    return AuthService.instance.esAdministrador() ||
        PermisosService.instance.puedeEliminar(rol, 'remitos');
  }

  Future<void> confirmarEliminar(Map<String, dynamic> remito) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar remito'),
        content: Text(
          '¿Eliminar definitivamente el remito ${remito['numero']}?\n\n'
          'Se anula el stock si hacía falta y se borra de este equipo y de la nube.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppVisuals.danger(Theme.of(context).colorScheme),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.eliminar(remito['id'] as int);
      await cargar();
    }
  }

  Future<void> _manejarAccionRemito(
    Map<String, dynamic> remito,
    String accion,
  ) async {
    if (accion == 'anular') {
      await confirmarAnular(remito);
      return;
    }
    if (accion == 'eliminar') {
      await confirmarEliminar(remito);
      return;
    }

    await service.actualizarEstadoPago(remito['id'], accion);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          accion == 'cobrado'
              ? 'Remito marcado como cobrado'
              : 'Remito marcado con pago parcial',
        ),
      ),
    );
    await cargar();
  }

  Color colorEstado(String estado) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (estado) {
      case 'confirmado':
        return AppVisuals.success(colorScheme);
      case 'anulado':
        return AppVisuals.danger(colorScheme);
      default:
        return AppVisuals.warning(colorScheme);
    }
  }

  Color colorEstadoPago(String estadoPago) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (estadoPago) {
      case 'cobrado':
        return AppVisuals.success(colorScheme);
      case 'parcial':
        return AppVisuals.info(colorScheme);
      default:
        return AppVisuals.warning(colorScheme);
    }
  }

  IconData iconoEstado(String estado) {
    switch (estado) {
      case 'confirmado':
        return Icons.verified_rounded;
      case 'anulado':
        return Icons.block_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  Widget estadoChip(String estado) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorEstado(estado).withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: colorEstado(estado),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget estadoPagoChip(String estadoPago) {
    final color = colorEstadoPago(estadoPago);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        estadoPago.toUpperCase(),
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
        title: 'Remitos',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_remitos',
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RemitoFormPage()),
          );
          cargar();
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: buscarController,
              onChanged: _filtrarRemitos,
              decoration: InputDecoration(
                hintText: 'Buscar remito o cliente...',
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
                : remitos.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay remitos.',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        itemCount: remitos.length,
                        itemBuilder: (context, i) {
                          final remito = remitos[i];
                          final estado = (remito['estado'] ?? 'pendiente').toString();
                          final estadoPago =
                              (remito['estadoPago'] ?? 'pendiente').toString();
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => verItems(remito),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: colorEstado(estado)
                                              .withValues(alpha: .15),
                                          child: Icon(
                                            iconoEstado(estado),
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
                                                remito['numero'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                remito['clienteNombre'] ??
                                                    'Sin cliente',
                                              ),
                                              Text(
                                                formatearFecha(
                                                  remito['fecha']?.toString(),
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
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '\$${((remito['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  onSelected: (value) =>
                                                      _manejarAccionRemito(
                                                    remito,
                                                    value,
                                                  ),
                                                  itemBuilder: (_) {
                                                    final items =
                                                        <PopupMenuEntry<String>>[
                                                      if (estado != 'anulado')
                                                        const PopupMenuItem(
                                                          value: 'cobrado',
                                                          child: Text(
                                                            'Marcar como cobrado',
                                                          ),
                                                        ),
                                                      if (estado != 'anulado')
                                                        const PopupMenuItem(
                                                          value: 'parcial',
                                                          child: Text(
                                                            'Pago parcial',
                                                          ),
                                                        ),
                                                      if (estado != 'anulado')
                                                        const PopupMenuItem(
                                                          value: 'anular',
                                                          child: Text('Anular'),
                                                        ),
                                                    ];
                                                    if (_puedeEliminarRemitos) {
                                                      items.add(
                                                        const PopupMenuItem(
                                                          value: 'eliminar',
                                                          child: Text(
                                                            'Eliminar',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    return items;
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              alignment: WrapAlignment.end,
                                              children: [
                                                estadoChip(estado),
                                                estadoPagoChip(estadoPago),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          tooltip: 'Comentarios internos',
                                          onPressed: () => showComentariosInternos(
                                            context,
                                            entidadTipo: 'remito',
                                            entidadId: '${remito['id']}',
                                            titulo:
                                                'Remito ${remito['numero'] ?? ''}',
                                          ),
                                          icon: const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Imprimir PDF',
                                          onPressed: () => imprimirRemito(remito),
                                          icon: const Icon(
                                            Icons.picture_as_pdf_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Compartir PDF',
                                          onPressed: () => compartirRemito(remito),
                                          icon: const Icon(
                                            Icons.share_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Compartir en chat',
                                          onPressed: () => showCompartirEnChatDialog(
                                            context,
                                            compartido: ChatCompartido(
                                              tipo: 'remito',
                                              idRef: '${remito['id']}',
                                              titulo:
                                                  'Remito ${remito['numero'] ?? ''}',
                                              subtitulo:
                                                  '${remito['clienteNombre'] ?? 'Sin cliente'} · '
                                                  '\$${((remito['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} · '
                                                  '${remito['estadoPago'] ?? ''}',
                                              datos: {
                                                'numero': remito['numero'],
                                                'total': remito['total'],
                                                'estado': remito['estado'],
                                                'estadoPago': remito['estadoPago'],
                                              },
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.forum_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
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
