import 'package:flutter/material.dart';

import 'backup_page.dart';
import 'comparacion_page.dart';
import 'importacion_clientes_page.dart';
import 'importacion_page.dart';
import 'importacion_proveedores_page.dart';
import 'plantillas_importacion_page.dart';
import '../theme/module_app_bar.dart';

class CentroImportacionesPage extends StatelessWidget {
  const CentroImportacionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final acciones = [
      _Accion(
        icon: Icons.table_chart_rounded,
        titulo: 'Plantillas Excel',
        subtitulo:
            'Descargá plantillas con el orden exacto de columnas\n'
            '(Código, Descripción, Precio1, Precio2…).',
        color: Colors.indigo,
        destino: const PlantillasImportacionPage(),
      ),
      _Accion(
        icon: Icons.upload_file_rounded,
        titulo: 'Importar Productos',
        subtitulo:
            'Carga masiva desde Excel o CSV.\nCrea o actualiza por código.',
        color: Colors.blue,
        destino: const ImportacionPage(),
      ),
      _Accion(
        icon: Icons.people_alt_rounded,
        titulo: 'Importar Clientes',
        subtitulo: 'Carga masiva de clientes desde Excel o CSV.',
        color: Colors.teal,
        destino: const ImportacionClientesPage(),
      ),
      _Accion(
        icon: Icons.local_shipping_rounded,
        titulo: 'Importar Proveedores',
        subtitulo: 'Carga masiva de proveedores desde Excel o CSV.',
        color: Colors.deepOrange,
        destino: const ImportacionProveedoresPage(),
      ),
      _Accion(
        icon: Icons.compare_arrows_rounded,
        titulo: 'Comparar Costos',
        subtitulo: 'Cargá una lista de proveedor y compará con la base.',
        color: Colors.orange,
        destino: const ComparacionPage(),
      ),
      _Accion(
        icon: Icons.cloud_upload_rounded,
        titulo: 'Copia de Seguridad',
        subtitulo: 'Exportá o importá la base de datos completa.',
        color: Colors.green,
        destino: const BackupPage(),
      ),
    ];

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Centro de importaciones'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hub_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro de Importaciones',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Plantillas Excel, importar productos/clientes/proveedores, '
                        'comparar listas y respaldar datos.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...acciones.map((a) => _TarjetaAccion(accion: a)),
          const SizedBox(height: 24),
          Text('Flujo sugerido', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          _buildFlujo(theme),
        ],
      ),
    );
  }

  Widget _buildFlujo(ThemeData theme) {
    final pasos = [
      '📥 Descargar plantilla Excel (productos / clientes / proveedores)',
      '✏️ Completar filas respetando el orden de columnas',
      '📤 Importar el archivo desde la opción correspondiente',
      '📊 Si llega lista de proveedor: Comparar costos',
      '✅ Seguir vendiendo con datos actualizados',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: pasos
              .asMap()
              .entries
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${e.key + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.value, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _Accion {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final Widget destino;

  const _Accion({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.destino,
  });
}

class _TarjetaAccion extends StatelessWidget {
  final _Accion accion;
  const _TarjetaAccion({required this.accion});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => accion.destino),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accion.color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(accion.icon, color: accion.color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accion.titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accion.subtitulo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
