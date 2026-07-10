import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/stock_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

class KardexPage extends StatefulWidget {
  final Producto producto;

  const KardexPage({super.key, required this.producto});

  @override
  State<KardexPage> createState() => _KardexPageState();
}

class _KardexPageState extends State<KardexPage> {
  final StockService _service = StockService();
  List<Map<String, dynamic>> _movimientos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _movimientos = await _service.obtenerMovimientos(productoId: widget.producto.id);
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  String _fechaHora(String texto) {
    final fecha = DateTime.tryParse(texto) ?? DateTime.now();
    final hora = '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} $hora';
  }

  Color _colorTipo(String tipo) {
    final cs = Theme.of(context).colorScheme;
    switch (tipo) {
      case 'entrada':
        return AppVisuals.success(cs);
      case 'salida':
        return AppVisuals.danger(cs);
      default:
        return AppVisuals.warning(cs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Kardex - ${widget.producto.descripcion}',
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _movimientos.isEmpty
              ? const Center(child: Text('Sin movimientos para este producto.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _movimientos.length,
                  itemBuilder: (context, index) {
                    final movimiento = _movimientos[index];
                    final color = _colorTipo((movimiento['tipo'] ?? '').toString());
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: .15),
                          child: Icon(Icons.swap_vert_rounded, color: color),
                        ),
                        title: Text(
                          '${(movimiento['tipo'] ?? '').toString().toUpperCase()} • ${movimiento['cantidad'] ?? 0} u.',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fechaHora((movimiento['fecha'] ?? '').toString())),
                            Text('Usuario: ${movimiento['usuario'] ?? 'sistema'}'),
                            Text(
                              'Stock: ${movimiento['stockAnterior'] ?? 0} → ${movimiento['stockNuevo'] ?? 0}',
                            ),
                            if ((movimiento['motivo'] ?? '').toString().isNotEmpty)
                              Text('Motivo: ${movimiento['motivo']}'),
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
