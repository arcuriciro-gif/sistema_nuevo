import 'package:flutter/material.dart';

import '../services/plantilla_importacion_service.dart';
import '../theme/module_app_bar.dart';
import 'importacion_clientes_page.dart';
import 'importacion_page.dart';
import 'importacion_proveedores_page.dart';
import 'comparacion_page.dart';

/// Pantalla para ver el orden de columnas y descargar plantillas Excel.
class PlantillasImportacionPage extends StatelessWidget {
  const PlantillasImportacionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Plantillas de importación'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Descargá la plantilla, completá las filas respetando el orden '
            'de columnas y después importá el archivo desde el Centro de importaciones.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _PlantillaCard(
            titulo: 'Productos',
            icon: Icons.inventory_2_rounded,
            color: Colors.blue,
            headers: PlantillaImportacionService.productosHeaders,
            obligatorio: 'Codigo',
            onDescargar: () => _descargar(
              context,
              () => PlantillaImportacionService.instance
                  .generarPlantillaProductos(),
            ),
            onImportar: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportacionPage()),
            ),
          ),
          _PlantillaCard(
            titulo: 'Clientes',
            icon: Icons.people_alt_rounded,
            color: Colors.teal,
            headers: PlantillaImportacionService.clientesHeaders,
            obligatorio: 'Nombre',
            onDescargar: () => _descargar(
              context,
              () => PlantillaImportacionService.instance
                  .generarPlantillaClientes(),
            ),
            onImportar: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ImportacionClientesPage(),
              ),
            ),
          ),
          _PlantillaCard(
            titulo: 'Proveedores',
            icon: Icons.local_shipping_rounded,
            color: Colors.deepOrange,
            headers: PlantillaImportacionService.proveedoresHeaders,
            obligatorio: 'Nombre',
            onDescargar: () => _descargar(
              context,
              () => PlantillaImportacionService.instance
                  .generarPlantillaProveedores(),
            ),
            onImportar: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ImportacionProveedoresPage(),
              ),
            ),
          ),
          _PlantillaCard(
            titulo: 'Lista proveedor (rangos de talle)',
            icon: Icons.straighten_rounded,
            color: Colors.purple,
            headers: PlantillaImportacionService.listaProveedorRangosHeaders,
            obligatorio: 'Articulo',
            onDescargar: () => _descargar(
              context,
              () => PlantillaImportacionService.instance
                  .generarPlantillaListaProveedorRangos(),
            ),
            onImportar: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ComparacionPage()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _descargar(
    BuildContext context,
    Future<dynamic> Function() generar,
  ) async {
    try {
      final file = await generar();
      await PlantillaImportacionService.instance.compartirArchivo(file);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plantilla lista:\n${file.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _PlantillaCard extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final Color color;
  final List<String> headers;
  final String obligatorio;
  final VoidCallback onDescargar;
  final VoidCallback onImportar;

  const _PlantillaCard({
    required this.titulo,
    required this.icon,
    required this.color,
    required this.headers,
    required this.obligatorio,
    required this.onDescargar,
    required this.onImportar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Orden de columnas:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            ...headers.asMap().entries.map(
                  (e) => Text(
                    '${e.key + 1}. ${e.value}'
                    '${e.value == obligatorio ? '  ← obligatorio' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onDescargar,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargar Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportar,
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Importar archivo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
