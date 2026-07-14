import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/module_app_bar.dart';

/// Manual profesional (PDF editorial) incluido en la app.
class ManualUsuarioPage extends StatefulWidget {
  const ManualUsuarioPage({super.key});

  @override
  State<ManualUsuarioPage> createState() => _ManualUsuarioPageState();
}

class _ManualUsuarioPageState extends State<ManualUsuarioPage> {
  static const _pdfAsset = 'assets/docs/MANUAL_DE_USO.pdf';

  bool _cargando = true;
  String? _error;
  Uint8List? _pdfBytes;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await rootBundle.load(_pdfAsset);
      if (!mounted) return;
      setState(() {
        _pdfBytes = data.buffer.asUint8List();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el manual PDF: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _compartirPdf() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/MANUAL_DE_USO_TataManager.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Manual Profesional — Tata.Manager',
        subject: 'Manual de uso Tata.Manager',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Manual de usuario',
        actions: [
          IconButton(
            tooltip: 'Compartir PDF',
            icon: const Icon(Icons.share_rounded),
            onPressed: (_cargando || _pdfBytes == null) ? null : _compartirPdf,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      child: const ListTile(
                        leading: Icon(Icons.menu_book_rounded),
                        title: Text('Manual Profesional · EL TATA'),
                        subtitle: Text(
                          'Edición editorial (67 págs). También está junto al .exe.',
                        ),
                      ),
                    ),
                    Expanded(
                      child: PdfPreview(
                        build: (_) async => _pdfBytes!,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        allowPrinting: true,
                        allowSharing: true,
                        pdfFileName: 'MANUAL_DE_USO_TataManager.pdf',
                      ),
                    ),
                  ],
                ),
    );
  }
}
