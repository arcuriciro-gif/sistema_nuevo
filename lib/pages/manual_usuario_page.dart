import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/module_app_bar.dart';

/// Manual de uso incluido en la app (Markdown + PDF).
class ManualUsuarioPage extends StatefulWidget {
  /// Si es true (p. ej. desde la pantalla de login), destaca registro y correo.
  final bool desdeLogin;

  const ManualUsuarioPage({super.key, this.desdeLogin = false});

  @override
  State<ManualUsuarioPage> createState() => _ManualUsuarioPageState();
}

class _ManualUsuarioPageState extends State<ManualUsuarioPage> {
  static const _mdAsset = 'assets/docs/MANUAL_DE_USO.md';
  static const _pdfAsset = 'assets/docs/MANUAL_DE_USO.pdf';

  String _contenido = '';
  bool _cargando = true;
  String? _error;
  bool _abriendoPdf = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final md = await rootBundle.loadString(_mdAsset);
      if (!mounted) return;
      setState(() {
        _contenido = md;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el manual: $e';
        _cargando = false;
      });
    }
  }

  Future<Uint8List> _bytesPdf() async {
    final data = await rootBundle.load(_pdfAsset);
    return data.buffer.asUint8List();
  }

  Future<File> _archivoPdfTemporal() async {
    final bytes = await _bytesPdf();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/MANUAL_DE_USO_TataManager.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _verPdf() async {
    if (_abriendoPdf) return;
    setState(() => _abriendoPdf = true);
    try {
      final bytes = await _bytesPdf();
      if (!mounted) return;

      // En Android el visor interno a veces falla; ofrecemos vista + compartir.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PdfManualPage(
            bytes: bytes,
            onCompartir: _compartirPdf,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir el PDF: $e'),
          action: SnackBarAction(
            label: 'Compartir',
            onPressed: _compartirPdf,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _abriendoPdf = false);
    }
  }

  Future<void> _compartirPdf() async {
    try {
      final file = await _archivoPdfTemporal();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: 'Manual de uso — Tata.Manager',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo compartir el PDF: $e')),
      );
    }
  }

  List<Widget> _construirContenido(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final line in _contenido.split('\n')) {
      final raw = line.trimRight();
      if (raw.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      if (raw.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              raw.substring(2),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else if (raw.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: Text(
              raw.substring(3),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (raw.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              raw.substring(4),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        );
      } else if (raw.startsWith('|') && raw.contains('---')) {
        continue;
      } else if (raw.startsWith('|')) {
        final cells = raw
            .split('|')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              cells.join('  ·  '),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        );
      } else if (raw.startsWith('- ') || raw.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(raw.substring(2))),
              ],
            ),
          ),
        );
      } else if (raw.startsWith('```')) {
        continue;
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(raw, style: theme.textTheme.bodyMedium),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Manual de usuario',
        actions: [
          IconButton(
            tooltip: 'Ver PDF',
            icon: _abriendoPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _cargando || _abriendoPdf ? null : _verPdf,
          ),
          IconButton(
            tooltip: 'Compartir / abrir PDF',
            icon: const Icon(Icons.share_rounded),
            onPressed: _cargando ? null : _compartirPdf,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    if (widget.desdeLogin)
                      Material(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: 0.7),
                        child: const ListTile(
                          leading: Icon(Icons.info_outline_rounded),
                          title: Text('Antes de iniciar sesión'),
                          subtitle: Text(
                            'Leé «Iniciar sesión» y «Pasos recomendados de uso». '
                            'También podés abrir o compartir el PDF.',
                          ),
                        ),
                      ),
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.menu_book_rounded),
                              title: const Text('Manual incluido en la app'),
                              subtitle: Text(
                                widget.desdeLogin
                                    ? 'Leelo acá abajo, o abrí/compartí el PDF.'
                                    : 'También está el PDF junto al .exe en Windows.',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed:
                                          _abriendoPdf ? null : _verPdf,
                                      icon: const Icon(
                                        Icons.picture_as_pdf_rounded,
                                      ),
                                      label: const Text('Ver PDF'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _compartirPdf,
                                      icon: const Icon(Icons.share_rounded),
                                      label: Text(
                                        defaultTargetPlatform ==
                                                TargetPlatform.android
                                            ? 'Abrir PDF'
                                            : 'Compartir',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: _construirContenido(context),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _PdfManualPage extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onCompartir;

  const _PdfManualPage({
    required this.bytes,
    required this.onCompartir,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Manual (PDF)',
        actions: [
          IconButton(
            tooltip: 'Compartir / abrir con otra app',
            icon: const Icon(Icons.share_rounded),
            onPressed: onCompartir,
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: 'MANUAL_DE_USO_TataManager.pdf',
      ),
    );
  }
}
