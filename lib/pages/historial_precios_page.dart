import 'package:flutter/material.dart';

import '../services/historial_precio_service.dart';
import '../services/producto_service.dart';
import '../theme/module_app_bar.dart';

/// Historial de cambios por producto: precios + auditoría.
class HistorialPreciosPage extends StatefulWidget {
  final int productoId;
  final String productoDescripcion;

  const HistorialPreciosPage({
    super.key,
    required this.productoId,
    required this.productoDescripcion,
  });

  @override
  State<HistorialPreciosPage> createState() => _HistorialPreciosPageState();
}

class _HistorialPreciosPageState extends State<HistorialPreciosPage> {
  final HistorialPrecioService service = HistorialPrecioService();
  final ProductoService productoService = ProductoService();

  List<Map<String, dynamic>> historial = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    historial = await productoService.historialCambios(widget.productoId);
    if (historial.isEmpty) {
      // Fallback a solo precios si no hay auditoría combinada
      final precios = await service.obtenerPorProducto(widget.productoId);
      historial = precios
          .map(
            (p) => {
              'tipo': 'precio',
              'fecha': p['fecha'],
              'usuario': p['usuario'],
              'detalle': p['motivo'] ?? 'Cambio de precio',
              'extra': p,
            },
          )
          .toList();
    }
    if (!mounted) return;
    setState(() => cargando = false);
  }

  String _formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Historial - ${widget.productoDescripcion}',
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : historial.isEmpty
              ? const Center(
                  child: Text('Este producto no tiene cambios registrados.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: historial.length,
                  itemBuilder: (context, i) {
                    final item = historial[i];
                    final tipo = item['tipo']?.toString() ?? 'auditoria';
                    final extra = item['extra'] as Map<String, dynamic>? ?? {};

                    if (tipo == 'precio') {
                      final costoAnterior =
                          (extra['costoAnterior'] as num?)?.toDouble() ?? 0;
                      final costoNuevo =
                          (extra['costoNuevo'] as num?)?.toDouble() ?? 0;
                      final precioAnterior =
                          (extra['precioAnterior'] as num?)?.toDouble() ?? 0;
                      final precioNuevo =
                          (extra['precioNuevo'] as num?)?.toDouble() ?? 0;
                      final porcentaje =
                          (extra['porcentaje'] as num?)?.toDouble() ?? 0;
                      final lista =
                          (extra['listaModificada'] ?? '').toString();
                      final subio = costoNuevo >= costoAnterior;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: subio
                                ? Colors.red.withValues(alpha: 0.15)
                                : Colors.green.withValues(alpha: 0.15),
                            child: Icon(
                              subio
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              color: subio ? Colors.red : Colors.green,
                            ),
                          ),
                          title: Text(
                            lista.isEmpty
                                ? 'Cambio de precio'
                                : 'Cambio · $lista',
                          ),
                          subtitle: Text(
                            'Costo \$${costoAnterior.toStringAsFixed(2)} → \$${costoNuevo.toStringAsFixed(2)}\n'
                            'Precio \$${precioAnterior.toStringAsFixed(2)} → \$${precioNuevo.toStringAsFixed(2)} '
                            '(${porcentaje.toStringAsFixed(1)}%)\n'
                            '${_formatearFecha(item['fecha']?.toString())} · ${item['usuario'] ?? ''}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            Icons.history_edu_rounded,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        title: Text(item['detalle']?.toString() ?? 'Cambio'),
                        subtitle: Text(
                          '${_formatearFecha(item['fecha']?.toString())} · ${item['usuario'] ?? ''}\n'
                          '${extra['accion'] ?? ''}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}
