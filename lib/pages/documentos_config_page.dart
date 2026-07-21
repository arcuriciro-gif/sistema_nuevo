import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/afip_service.dart';
import '../services/document_numbering_service.dart';
import '../theme/module_app_bar.dart';

/// Configuración de numeración de documentos y AFIP/ARCA.
class DocumentosConfigPage extends StatefulWidget {
  const DocumentosConfigPage({super.key});

  @override
  State<DocumentosConfigPage> createState() => _DocumentosConfigPageState();
}

class _DocumentosConfigPageState extends State<DocumentosConfigPage> {
  final Map<String, TextEditingController> _prefijos = {};
  final Map<String, TextEditingController> _proximos = {};
  final _cuitCtrl = TextEditingController();
  final _pvCtrl = TextEditingController();
  bool _afipEnabled = false;
  String _ambiente = 'homo';
  String _certPath = '';
  String _keyPath = '';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final numbering = DocumentNumberingService.instance;
    for (final tipo in DocumentNumberingService.tipos) {
      _prefijos[tipo] = TextEditingController(text: numbering.prefijo(tipo));
      _proximos[tipo] = TextEditingController(
        text: '${numbering.proximoForzado(tipo)}',
      );
    }
    final afip = AfipConfigService.instance;
    _afipEnabled = afip.enabled;
    _ambiente = afip.ambiente;
    _cuitCtrl.text = afip.cuitEmisor;
    _pvCtrl.text = '${afip.puntoVenta}';
    _certPath = afip.certPath;
    _keyPath = afip.keyPath;
  }

  @override
  void dispose() {
    for (final c in _prefijos.values) {
      c.dispose();
    }
    for (final c in _proximos.values) {
      c.dispose();
    }
    _cuitCtrl.dispose();
    _pvCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile(void Function(String path) onPicked) async {
    final result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => onPicked(result.files.single.path!));
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final prefsMap = <String, String>{};
    final nextMap = <String, int>{};
    for (final tipo in DocumentNumberingService.tipos) {
      prefsMap[tipo] = _prefijos[tipo]!.text.trim();
      nextMap[tipo] = int.tryParse(_proximos[tipo]!.text.trim()) ?? 0;
    }
    await DocumentNumberingService.instance.guardar(
      prefijos: prefsMap,
      proximos: nextMap,
    );
    await AfipConfigService.instance.guardar(
      enabled: _afipEnabled,
      ambiente: _ambiente,
      puntoVenta: int.tryParse(_pvCtrl.text.trim()) ?? 1,
      cuitEmisor: _cuitCtrl.text.trim(),
      certPath: _certPath,
      keyPath: _keyPath,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración de documentos guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Documentos y AFIP'),
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
          ...DocumentNumberingService.tipos.map((tipo) {
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
          const Divider(height: 32),
          Text(
            'AFIP / ARCA',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Base lista para facturación electrónica. '
            'Con certificados se conectará la autorización real (WSAA/WSFE).',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar módulo AFIP'),
            value: _afipEnabled,
            onChanged: (v) => setState(() => _afipEnabled = v),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_ambiente),
            initialValue: _ambiente,
            decoration: const InputDecoration(
              labelText: 'Ambiente',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'homo', child: Text('Homologación')),
              DropdownMenuItem(value: 'prod', child: Text('Producción')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _ambiente = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cuitCtrl,
            decoration: const InputDecoration(
              labelText: 'CUIT emisor',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pvCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Punto de venta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _certPath.isEmpty ? 'Certificado (.crt/.pem)' : _certPath,
            ),
            trailing: OutlinedButton(
              onPressed: () => _pickFile((p) => _certPath = p),
              child: const Text('Elegir'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_keyPath.isEmpty ? 'Clave privada (.key)' : _keyPath),
            trailing: OutlinedButton(
              onPressed: () => _pickFile((p) => _keyPath = p),
              child: const Text('Elegir'),
            ),
          ),
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
