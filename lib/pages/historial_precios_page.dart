import 'package:flutter/material.dart';

import '../services/historial_precio_service.dart';
import '../theme/module_app_bar.dart';

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

  List<Map<String, dynamic>> historial = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    historial = await service.obtenerPorProducto(widget.productoId);
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
                    final costoAnterior =
                        (item['costoAnterior'] as num?)?.toDouble() ?? 0;
                    final costoNuevo =
                        (item['costoNuevo'] as num?)?.toDouble() ?? 0;
                    final precioAnterior =
                        (item['precioAnterior'] as num?)?.toDouble() ?? 0;
                    final precioNuevo =
                        (item['precioNuevo'] as num?)?.toDouble() ?? 0;
                    final porcentaje =
                        (item['porcentaje'] as num?)?.toDouble() ?? 0;
                    final lista =
                        (item['listaModificada'] ?? '').toString();
                    final subio = costoNuevo >= costoAnterior;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (subio ? Colors.red : Colors.green)
                              .withValues(alpha: .15),
                          child: Icon(
                            subio
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            color: subio ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          'Costo: \$${costoAnterior.toStringAsFixed(2)} → \$${costoNuevo.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (precioAnterior > 0 || precioNuevo > 0)
                              Text(
                                'Precio: \$${precioAnterior.toStringAsFixed(2)} → \$${precioNuevo.toStringAsFixed(2)}'
                                '${porcentaje != 0 ? '  (${porcentaje >= 0 ? '+' : ''}${porcentaje.toStringAsFixed(1)}%)' : ''}',
                              ),
                            if (lista.isNotEmpty)
                              Text('Lista: $lista'),
                            Text(_formatearFecha(item['fecha']?.toString())),
                            Text('Usuario: ${item['usuario'] ?? '-'}'),
                            if ((item['motivo'] ?? '').toString().isNotEmpty)
                              Text('Motivo: ${item['motivo']}'),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}
