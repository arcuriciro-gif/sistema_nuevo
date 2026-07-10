import 'dart:io';

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

  Future<void> _verPdf() async {
    final bytes = await _bytesPdf();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: buildModuleAppBar(context, title: 'Manual (PDF)'),
          body: PdfPreview(
            build: (_) async => bytes,
            canChangeOrientation: false,
            canChangePageFormat: false,
            allowPrinting: true,
            allowSharing: true,
          ),
        ),
      ),
    );
  }

  Future<void> _compartirPdf() async {
    final bytes = await _bytesPdf();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/MANUAL_DE_USO_TataManager.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Manual de uso — Tata.Manager',
      ),
    );
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
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _cargando ? null : _verPdf,
          ),
          IconButton(
            tooltip: 'Compartir PDF',
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
                            'Leé la sección «Primeros pasos: registro y correo» '
                            'y abrí el PDF si preferís imprimirlo o enviarlo.',
                          ),
                        ),
                      ),
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.5),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_rounded),
                        title: const Text('Manual incluido en la app'),
                        subtitle: Text(
                          widget.desdeLogin
                              ? 'Podés leerlo acá o abrir el PDF sin necesidad de entrar.'
                              : 'En Windows también está el PDF junto al .exe '
                                  '(MANUAL_DE_USO.pdf).',
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: _verPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
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
