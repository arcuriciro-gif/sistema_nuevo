import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../services/branding_service.dart';
import '../services/pdf_service.dart';
import '../theme/module_app_bar.dart';

/// Editor único de plantilla de impresión/PDF.
/// Guardás una vez y se aplica a remitos, facturas, presupuestos y notas.
class PlantillaImpresionPage extends StatefulWidget {
  const PlantillaImpresionPage({super.key});

  @override
  State<PlantillaImpresionPage> createState() => _PlantillaImpresionPageState();
}

class _PlantillaImpresionPageState extends State<PlantillaImpresionPage> {
  final _encabezadoCtrl = TextEditingController();
  final _pieCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _margenCtrl = TextEditingController();
  final _leyendaCtrl = TextEditingController();
  final _diasVencCtrl = TextEditingController();

  String _logoPath = '';
  String _firmaPath = '';
  String _selloPath = '';
  String _papelPdf = 'a4';
  bool _mostrarFirma = true;
  bool _mostrarSello = true;
  bool _mostrarEstadoPago = true;
  bool _guardando = false;
  bool _previsualizando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _encabezadoCtrl.dispose();
    _pieCtrl.dispose();
    _colorCtrl.dispose();
    _margenCtrl.dispose();
    _leyendaCtrl.dispose();
    _diasVencCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    final b = BrandingService.instance;
    _encabezadoCtrl.text = b.encabezadoPdf;
    _pieCtrl.text = b.piePdf;
    _colorCtrl.text = b.colorPdf;
    _margenCtrl.text = b.margenPdfMm.toStringAsFixed(0);
    _leyendaCtrl.text = b.leyendaLegal;
    _diasVencCtrl.text = '${b.diasVencimiento}';
    setState(() {
      _logoPath = b.logoPath;
      _firmaPath = b.firmaPath;
      _selloPath = b.selloPath;
      _papelPdf = b.papelPdf;
      _mostrarFirma = b.mostrarFirma;
      _mostrarSello = b.mostrarSello;
      _mostrarEstadoPago = b.mostrarEstadoPago;
    });
  }

  Future<String?> _elegirYPersistir(String nombreBase) async {
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (img == null) return null;
    return BrandingService.instance.persistirImagen(img.path, nombreBase);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    await BrandingService.instance.guardarPlantilla(
      encabezadoPdf: _encabezadoCtrl.text.trim(),
      piePdf: _pieCtrl.text.trim(),
      colorPdf: _colorCtrl.text.trim().replaceAll('#', '').isEmpty
          ? 'FF7A00'
          : _colorCtrl.text.trim().replaceAll('#', ''),
      papelPdf: _papelPdf,
      margenPdfMm: double.tryParse(_margenCtrl.text.trim()) ?? 10,
      firmaPath: _firmaPath,
      selloPath: _selloPath,
      mostrarFirma: _mostrarFirma,
      mostrarSello: _mostrarSello,
      mostrarEstadoPago: _mostrarEstadoPago,
      leyendaLegal: _leyendaCtrl.text.trim(),
      logoPath: _logoPath,
      diasVencimiento: int.tryParse(_diasVencCtrl.text.trim()) ?? 30,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Plantilla guardada. Se aplica a todos los PDF e impresiones.',
        ),
      ),
    );
  }

  Future<void> _vistaPrevia() async {
    setState(() => _previsualizando = true);
    // Guardar primero para que la preview use valores actuales
    await _guardar();
    try {
      final bytes = await PdfService().generateRemitoPdf(
        {
          'numero': 'PREV-000001',
          'fecha': DateTime.now().toIso8601String(),
          'total': 15000,
          'descuento': 0,
          'estadoPago': 'parcial',
          'observaciones': 'Documento de vista previa',
        },
        [
          {
            'descripcion': 'Producto de ejemplo A',
            'cantidad': 2,
            'precioUnitario': 5000,
            'subtotal': 10000,
          },
          {
            'descripcion': 'Producto de ejemplo B',
            'cantidad': 1,
            'precioUnitario': 5000,
            'subtotal': 5000,
          },
        ],
        'Cliente de ejemplo',
        clienteDireccion: 'Calle Falsa 123',
        clienteTelefono: '11 0000-0000',
        tipoDocumento: 'VISTA PREVIA',
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la vista previa: $e')),
      );
    } finally {
      if (mounted) setState(() => _previsualizando = false);
    }
  }

  Widget _imagenBox({
    required String label,
    required String path,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 96,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: path.isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: cs.primary),
                        const SizedBox(height: 4),
                        Text(label, textAlign: TextAlign.center),
                      ],
                    )
                  : Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
          if (path.isNotEmpty)
            TextButton(onPressed: onClear, child: const Text('Quitar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final branding = BrandingService.instance;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Plantilla de impresión',
        actions: [
          IconButton(
            tooltip: 'Vista previa PDF',
            onPressed: _previsualizando ? null : _vistaPrevia,
            icon: _previsualizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Una sola plantilla para todos los documentos',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lo que guardes acá se usa al imprimir o exportar PDF de '
                    'remitos, facturas, presupuestos y notas de entrega.\n'
                    'Negocio actual: ${branding.nombre}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Logo del documento',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _imagenBox(
                label: 'Logo PDF',
                path: _logoPath,
                onPick: () async {
                  final path = await _elegirYPersistir('logo');
                  if (path != null) setState(() => _logoPath = path);
                },
                onClear: () => setState(() => _logoPath = ''),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _encabezadoCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Encabezado / leyenda superior',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pieCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Pie de página',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _leyendaCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Leyenda legal / observaciones fijas',
              border: OutlineInputBorder(),
              helperText: 'Ej: Documento no válido como factura fiscal',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _colorCtrl,
            decoration: const InputDecoration(
              labelText: 'Color de encabezado (hex)',
              border: OutlineInputBorder(),
              prefixText: '#',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_papelPdf),
            initialValue: _papelPdf,
            decoration: const InputDecoration(
              labelText: 'Tamaño de papel',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'a4', child: Text('A4')),
              DropdownMenuItem(value: 'ticket_80', child: Text('Ticket 80 mm')),
              DropdownMenuItem(value: 'ticket_58', child: Text('Ticket 58 mm')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _papelPdf = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _margenCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Márgenes (mm)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diasVencCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Días de vencimiento CC (por defecto)',
              border: OutlineInputBorder(),
              helperText: 'Se usa al crear ventas a cuenta corriente',
            ),
          ),
          const SizedBox(height: 16),
          Text('Firma y sello',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _imagenBox(
                label: 'Firma',
                path: _firmaPath,
                onPick: () async {
                  final path = await _elegirYPersistir('firma');
                  if (path != null) setState(() => _firmaPath = path);
                },
                onClear: () => setState(() => _firmaPath = ''),
              ),
              const SizedBox(width: 12),
              _imagenBox(
                label: 'Sello',
                path: _selloPath,
                onPick: () async {
                  final path = await _elegirYPersistir('sello');
                  if (path != null) setState(() => _selloPath = path);
                },
                onClear: () => setState(() => _selloPath = ''),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar firma en PDF'),
            value: _mostrarFirma,
            onChanged: (v) => setState(() => _mostrarFirma = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar sello en PDF'),
            value: _mostrarSello,
            onChanged: (v) => setState(() => _mostrarSello = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar estado de pago'),
            value: _mostrarEstadoPago,
            onChanged: (v) => setState(() => _mostrarEstadoPago = v),
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
              label: const Text('Guardar plantilla'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _previsualizando ? null : _vistaPrevia,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Vista previa PDF'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
