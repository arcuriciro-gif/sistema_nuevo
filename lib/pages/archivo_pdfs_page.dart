import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/utils/media_path.dart';
import '../models/documento_cliente.dart';
import '../services/documento_cliente_service.dart';
import '../theme/module_app_bar.dart';

/// Carpeta de PDFs archivados por cliente (sincronizada entre dispositivos).
class ArchivoPdfsPage extends StatefulWidget {
  const ArchivoPdfsPage({super.key});

  @override
  State<ArchivoPdfsPage> createState() => _ArchivoPdfsPageState();
}

class _ArchivoPdfsPageState extends State<ArchivoPdfsPage> {
  Map<String, List<DocumentoCliente>> _grupos = {};
  bool _cargando = true;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onRefresh);
    _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final grupos =
        await DocumentoClienteService.instance.listarAgrupadoPorCliente();
    if (!mounted) return;
    setState(() {
      _grupos = grupos;
      _cargando = false;
    });
  }

  Future<void> _compartir(DocumentoCliente doc) async {
    try {
      File? file;
      if (doc.localPath.isNotEmpty && File(doc.localPath).existsSync()) {
        file = File(doc.localPath);
      } else if (esUrlRemota(doc.url)) {
        final resp = await http.get(Uri.parse(doc.url));
        if (resp.statusCode != 200) {
          throw StateError('No se pudo descargar el PDF');
        }
        final dir = await getTemporaryDirectory();
        file = File('${dir.path}/${doc.nombreArchivo}');
        await file.writeAsBytes(resp.bodyBytes);
      }
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF no disponible aún')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${doc.tipo} ${doc.numero} — ${doc.clienteNombre}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al compartir: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _filtro.toLowerCase().trim();
    final keys = _grupos.keys.where((k) {
      if (filtro.isEmpty) return true;
      if (k.toLowerCase().contains(filtro)) return true;
      return _grupos[k]!.any(
        (d) =>
            d.numero.toLowerCase().contains(filtro) ||
            d.tipo.toLowerCase().contains(filtro),
      );
    }).toList()
      ..sort();

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Archivo PDF',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar cliente o número…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : keys.isEmpty
                    ? const Center(
                        child: Text(
                          'Todavía no hay PDFs archivados.\n'
                          'Al compartir un remito o factura se guarda acá.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: keys.length,
                        itemBuilder: (context, index) {
                          final cliente = keys[index];
                          final docs = _grupos[cliente]!;
                          return ExpansionTile(
                            leading: const Icon(Icons.folder_rounded),
                            title: Text(cliente),
                            subtitle: Text('${docs.length} documento(s)'),
                            children: docs.map((d) {
                              final fecha =
                                  '${d.fecha.day.toString().padLeft(2, '0')}/'
                                  '${d.fecha.month.toString().padLeft(2, '0')}/'
                                  '${d.fecha.year}';
                              return ListTile(
                                leading: const Icon(Icons.picture_as_pdf),
                                title: Text('${d.tipo} ${d.numero}'.trim()),
                                subtitle: Text('$fecha · ${d.creadoPor}'),
                                trailing: IconButton(
                                  tooltip: 'Compartir / enviar',
                                  icon: const Icon(Icons.share_rounded),
                                  onPressed: () => _compartir(d),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
