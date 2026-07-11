import 'package:flutter/material.dart';

import '../services/historial_precio_service.dart';
import '../services/producto_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

/// Historial unificado del producto: precios, stock y cambios (usuario + fecha).
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

class _HistorialPreciosPageState extends State<HistorialPreciosPage>
    with SingleTickerProviderStateMixin {
  final HistorialPrecioService service = HistorialPrecioService();
  final ProductoService productoService = ProductoService();

  late final TabController _tabs;
  List<Map<String, dynamic>> historial = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    historial = await productoService.historialCambios(widget.productoId);
    if (historial.isEmpty) {
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

  List<Map<String, dynamic>> _filtrar(String? tipo) {
    if (tipo == null) return historial;
    return historial.where((e) => e['tipo'] == tipo).toList();
  }

  String _formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  Widget _lista(List<Map<String, dynamic>> items) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return const Center(child: Text('Sin registros en esta sección.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final tipo = item['tipo']?.toString() ?? 'auditoria';
        final extra = item['extra'] as Map<String, dynamic>? ?? {};

        if (tipo == 'precio') {
          final costoAnterior =
              (extra['costoAnterior'] as num?)?.toDouble() ?? 0;
          final costoNuevo = (extra['costoNuevo'] as num?)?.toDouble() ?? 0;
          final precioAnterior =
              (extra['precioAnterior'] as num?)?.toDouble() ?? 0;
          final precioNuevo =
              (extra['precioNuevo'] as num?)?.toDouble() ?? 0;
          final porcentaje = (extra['porcentaje'] as num?)?.toDouble() ?? 0;
          final lista = (extra['listaModificada'] ?? '').toString();
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
                lista.isEmpty ? 'Cambio de precio' : 'Cambio · $lista',
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

        if (tipo == 'stock') {
          final movTipo = (extra['tipo'] ?? '').toString();
          final color = movTipo == 'entrada'
              ? AppVisuals.success(cs)
              : movTipo == 'salida'
                  ? AppVisuals.danger(cs)
                  : AppVisuals.warning(cs);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(Icons.swap_vert_rounded, color: color),
              ),
              title: Text(item['detalle']?.toString() ?? 'Stock'),
              subtitle: Text(
                'Stock ${(extra['stockAnterior'] ?? '-')} → ${(extra['stockNuevo'] ?? '-')}\n'
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Historial · ${widget.productoDescripcion}',
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Todo'),
            Tab(text: 'Precios'),
            Tab(text: 'Stock'),
            Tab(text: 'Cambios'),
          ],
        ),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : historial.isEmpty
              ? const Center(
                  child: Text('Este producto no tiene cambios registrados.'),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _lista(_filtrar(null)),
                    _lista(_filtrar('precio')),
                    _lista(_filtrar('stock')),
                    _lista(_filtrar('auditoria')),
                  ],
                ),
    );
  }
}
