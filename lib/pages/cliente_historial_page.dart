import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/cliente.dart';
import '../services/pdf_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';

class ClienteHistorialPage extends StatefulWidget {
  final Cliente cliente;

  const ClienteHistorialPage({super.key, required this.cliente});

  @override
  State<ClienteHistorialPage> createState() => _ClienteHistorialPageState();
}

class _ClienteHistorialPageState extends State<ClienteHistorialPage> {
  final RemitoService remitoService = RemitoService();
  final PdfService pdfService = PdfService();

  List<Map<String, dynamic>> remitos = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    setState(() => cargando = true);
    remitos = await remitoService.obtenerPorCliente(widget.cliente.id ?? 0);
    if (!mounted) return;
    setState(() => cargando = false);
  }

  String formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  Color colorEstado(String estado) {
    switch (estado) {
      case 'confirmado':
        return Colors.green;
      case 'anulado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> verItems(Map<String, dynamic> remito) async {
    final items = await remitoService.obtenerItems(remito['id']);
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
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.orange),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.orange,
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
    return remitoService.obtenerItems(remito['id']);
  }

  Future<void> imprimirRemito(Map<String, dynamic> remito) async {
    final items = await _obtenerPdfItems(remito);
    final pdf = await pdfService.generateRemitoPdf(
      remito,
      items,
      widget.cliente.nombre,
    );
    if (pdf.isEmpty) return;
    await Printing.layoutPdf(onLayout: (_) async => pdf);
  }

  Future<void> compartirRemito(Map<String, dynamic> remito) async {
    final items = await _obtenerPdfItems(remito);
    final pdf = await pdfService.generateRemitoPdf(
      remito,
      items,
      widget.cliente.nombre,
    );
    if (pdf.isEmpty) return;
    final archivo = await pdfService.guardarPdf(
      pdf,
      'remito_${remito['numero']}.pdf',
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(archivo.path)]),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Historial del cliente'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cliente.nombre,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.cliente.telefono.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Teléfono: ${widget.cliente.telefono}'),
                ],
                if (widget.cliente.direccion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Dirección: ${widget.cliente.direccion}'),
                ],
              ],
            ),
          ),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : remitos.isEmpty
                    ? const Center(
                        child: Text(
                          'Este cliente no tiene remitos.',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        itemCount: remitos.length,
                        itemBuilder: (context, index) {
                          final remito = remitos[index];
                          final estado = remito['estado'] ?? 'pendiente';
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
                                      children: [
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
                                              Text(formatearFecha(remito['fecha']?.toString())),
                                            ],
                                          ),
                                        ),
                                        estadoChip(estado),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '\$${((remito['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Imprimir PDF',
                                          onPressed: () => imprimirRemito(remito),
                                          icon: const Icon(Icons.picture_as_pdf,
                                              color: Colors.orange),
                                        ),
                                        IconButton(
                                          tooltip: 'Compartir PDF',
                                          onPressed: () => compartirRemito(remito),
                                          icon: const Icon(Icons.share,
                                              color: Colors.orange),
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
