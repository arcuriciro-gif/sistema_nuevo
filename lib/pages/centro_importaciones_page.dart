import 'package:flutter/material.dart';

import 'backup_page.dart';
import 'comparacion_page.dart';
import 'importacion_page.dart';

class CentroImportacionesPage extends StatelessWidget {
  const CentroImportacionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final acciones = [
      _Accion(
        icon: Icons.upload_file_rounded,
        titulo: 'Importar Productos',
        subtitulo: 'Carga masiva desde Excel o CSV.\nCrea o actualiza por código.',
        color: Colors.blue,
        destino: const ImportacionPage(),
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
      // AppBar solo cuando es abierta como ruta apilada (ej: desde un acceso directo)
      appBar: ModalRoute.of(context)?.canPop == true
          ? AppBar(title: const Text('Centro de Importaciones'))
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner descriptivo
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
                        'Todas las tareas masivas en un solo lugar: '
                        'importar productos, comparar listas de proveedores y respaldar datos.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tarjetas de acciones
          ...acciones.map((a) => _TarjetaAccion(accion: a)),

          const SizedBox(height: 24),

          // Flujo sugerido
          Text(
            'Flujo sugerido',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          _buildFlujo(theme),
        ],
      ),
    );
  }

  Widget _buildFlujo(ThemeData theme) {
    final pasos = [
      '📥 Importar productos (primera carga ~2500 productos)',
      '🛍 Trabajar normalmente',
      '📊 Llega lista nueva de proveedor (Febo, Bisso...)',
      '🔄 Comparar costos',
      '💰 Actualizar costos (solo modifica el costo)',
      '✅ Seguir vendiendo con costos actualizados',
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
                          color: theme.colorScheme.primary.withValues(alpha: .15),
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
                        child: Text(
                          e.value,
                          style: theme.textTheme.bodySmall,
                        ),
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
