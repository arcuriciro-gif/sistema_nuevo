import 'package:flutter/material.dart';

import '../models/venta.dart';
import '../services/venta_service.dart';
import '../theme/app_visuals.dart';
import 'venta_factura_page.dart';

class VentasPage extends StatefulWidget {
  const VentasPage({super.key});

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> {
  final VentaService _service = VentaService();
  final TextEditingController _buscarCtrl = TextEditingController();

  List<Venta> _todas = [];
  List<Venta> _filtradas = [];
  String _tipoFiltro = 'todos';
  bool _cargando = true;

  static const _tipos = {
    'todos': 'Todos',
    'factura_a': 'Factura A',
    'factura_b': 'Factura B',
    'factura_c': 'Factura C',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _todas = await _service.obtenerTodas();
    _aplicarFiltro();
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  void _aplicarFiltro() {
    final q = _buscarCtrl.text.toLowerCase();
    _filtradas = _todas.where((v) {
      final tipoOk = _tipoFiltro == 'todos' || v.tipo == _tipoFiltro;
      final textoOk = q.isEmpty ||
          v.numero.toLowerCase().contains(q) ||
          (v.clienteNombre?.toLowerCase().contains(q) ?? false);
      return tipoOk && textoOk;
    }).toList();
    setState(() {});
  }

  Future<void> _nuevaVenta(String tipo) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => VentaFacturaPage(tipo: tipo)),
    );
    await _cargar();
  }

  Future<void> _verDetalle(Venta venta) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VentaFacturaPage(tipo: venta.tipo, ventaId: venta.id),
      ),
    );
    await _cargar();
  }

  Color _colorTipo(String tipo, ColorScheme cs) {
    switch (tipo) {
      case 'factura_a':
        return AppVisuals.danger(cs);
      case 'factura_b':
        return AppVisuals.info(cs);
      case 'factura_c':
        return AppVisuals.success(cs);
      default:
        return AppVisuals.neutral(cs);
    }
  }

  Color _colorEstadoPago(String estado, ColorScheme cs) {
    switch (estado) {
      case 'cobrado':
        return AppVisuals.success(cs);
      case 'parcial':
        return AppVisuals.warning(cs);
      default:
        return AppVisuals.danger(cs);
    }
  }

  String _formatFecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/'
      '${fecha.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_ventas',
        onPressed: () => _mostrarMenuNueva(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscarCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por número o cliente...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _aplicarFiltro(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _tipoFiltro,
                  items: _tipos.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _tipoFiltro = v;
                      _aplicarFiltro();
                    }
                  },
                ),
              ],
            ),
          ),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filtradas.isEmpty)
            const Expanded(
              child: Center(child: Text('No hay ventas registradas.')),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filtradas.length,
                itemBuilder: (context, i) {
                  final v = _filtradas[i];
                  final colorTipo = _colorTipo(v.tipo, cs);
                  return Card(
                    child: ListTile(
                      onTap: () => _verDetalle(v),
                      leading: CircleAvatar(
                        backgroundColor: colorTipo.withValues(alpha: .15),
                        child: Text(
                          v.tipo == 'factura_a'
                              ? 'A'
                              : v.tipo == 'factura_b'
                                  ? 'B'
                                  : v.tipo == 'factura_c'
                                      ? 'C'
                                      : 'T',
                          style: TextStyle(
                            color: colorTipo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        '${v.tipoLabel}  ${v.numero}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.clienteNombre ?? 'Sin cliente'),
                          Text(_formatFecha(v.fecha)),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${v.total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _colorEstadoPago(v.estadoPago, cs)
                                  .withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              v.estadoPago,
                              style: TextStyle(
                                fontSize: 11,
                                color: _colorEstadoPago(v.estadoPago, cs),
                              ),
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _mostrarMenuNueva() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Tipo de comprobante',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('A')),
              title: const Text('Factura A'),
              subtitle: const Text('Responsable Inscripto — con IVA discriminado'),
              onTap: () {
                Navigator.pop(context);
                _nuevaVenta('factura_a');
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('B')),
              title: const Text('Factura B'),
              subtitle: const Text('Consumidor Final — IVA incluido'),
              onTap: () {
                Navigator.pop(context);
                _nuevaVenta('factura_b');
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('C')),
              title: const Text('Factura C'),
              subtitle: const Text('Monotributista — sin IVA'),
              onTap: () {
                Navigator.pop(context);
                _nuevaVenta('factura_c');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
