import 'package:flutter/material.dart';

import '../services/document_numbering_service.dart';
import '../theme/module_app_bar.dart';

/// Configuración de numeración de documentos (comprobantes).
class DocumentosConfigPage extends StatefulWidget {
  const DocumentosConfigPage({super.key});

  @override
  State<DocumentosConfigPage> createState() => _DocumentosConfigPageState();
}

class _DocumentosConfigPageState extends State<DocumentosConfigPage> {
  final Map<String, TextEditingController> _prefijos = {};
  final Map<String, TextEditingController> _proximos = {};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final numbering = DocumentNumberingService.instance;
    for (final tipo in DocumentNumberingService.tiposVisibles) {
      _prefijos[tipo] = TextEditingController(text: numbering.prefijo(tipo));
      _proximos[tipo] = TextEditingController(
        text: '${numbering.proximoForzado(tipo)}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _prefijos.values) {
      c.dispose();
    }
    for (final c in _proximos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final prefsMap = <String, String>{};
    final nextMap = <String, int>{};
    for (final tipo in DocumentNumberingService.tiposVisibles) {
      prefsMap[tipo] = _prefijos[tipo]!.text.trim();
      nextMap[tipo] = int.tryParse(_proximos[tipo]!.text.trim()) ?? 0;
    }
    await DocumentNumberingService.instance.guardar(
      prefijos: prefsMap,
      proximos: nextMap,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Numeración guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Numeración de documentos'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Numeración',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Definí el prefijo y, si querés, el próximo número forzado '
            '(0 = seguir el correlativo automático).',
          ),
          const SizedBox(height: 12),
          ...DocumentNumberingService.tiposVisibles.map((tipo) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(DocumentNumberingService.labelTipo(tipo)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _prefijos[tipo],
                      decoration: const InputDecoration(
                        labelText: 'Prefijo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _proximos[tipo],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Próximo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}
