import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/producto.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import '../services/cliente_service.dart';
import '../services/producto_service.dart';
import '../services/venta_service.dart';
import '../theme/app_visuals.dart';

// ---------------------------------------------------------------------------
// Ítem del carrito (temporal, no persistido)
// ---------------------------------------------------------------------------
class _ItemCarrito {
  final Producto producto;
  int cantidad;
  double precioUnitario;

  _ItemCarrito({required this.producto, this.cantidad = 1})
      : precioUnitario = producto.precio;

  double get subtotal => cantidad * precioUnitario;
}

// ---------------------------------------------------------------------------
// Página de Factura A / B / C
// ---------------------------------------------------------------------------
class VentaFacturaPage extends StatefulWidget {
  final String tipo;
  final int? ventaId;

  const VentaFacturaPage({super.key, required this.tipo, this.ventaId});

  @override
  State<VentaFacturaPage> createState() => _VentaFacturaPageState();
}

class _VentaFacturaPageState extends State<VentaFacturaPage> {
  final VentaService _ventaSvc = VentaService();
  final ProductoService _prodSvc = ProductoService();
  final ClienteService _clienteSvc = ClienteService();

  final TextEditingController _busquedaCtrl = TextEditingController();
  final TextEditingController _obsCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  List<Producto> _resultados = [];
  final List<_ItemCarrito> _carrito = [];
  List<Cliente> _clientes = [];
  Cliente? _clienteSeleccionado;

  bool _buscando = false;
  bool _finalizando = false;
  bool _modoLectura = false;
  Venta? _ventaExistente;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
    if (widget.ventaId != null) _cargarVentaExistente();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _obsCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    _clientes = await _clienteSvc.obtenerTodos();
    if (mounted) setState(() {});
  }

  Future<void> _cargarVentaExistente() async {
    final venta = await _ventaSvc.obtenerPorId(widget.ventaId!);
    if (venta == null) return;
    final items = await _ventaSvc.obtenerItems(widget.ventaId!);
    if (!mounted) return;
    setState(() {
      _ventaExistente = venta;
      _modoLectura = true;
      _obsCtrl.text = venta.observaciones;
      _descCtrl.text = venta.descuento.toStringAsFixed(2);
    });
    if (venta.clienteId != null && _clientes.isNotEmpty) {
      await _cargarClientes();
      final idx = _clientes.indexWhere((c) => c.id == venta.clienteId);
      if (idx >= 0 && mounted) {
        setState(() => _clienteSeleccionado = _clientes[idx]);
      }
    }
    // Populate carrito from saved items (display only)
    for (final item in items) {
      final prod = Producto(
        id: item.productoId,
        codigo: '',
        descripcion: item.productoDescripcion,
        marca: '',
        categoria: '',
        proveedor: '',
        ubicacion: '',
        stock: 0,
        costo: 0,
        precio: item.precio,
        observaciones: '',
        foto: '',
      );
      _carrito.add(
        _ItemCarrito(producto: prod, cantidad: item.cantidad)
          ..precioUnitario = item.precio,
      );
    }
    if (mounted) setState(() {});
  }

  // ── Búsqueda de productos ──────────────────────────────────────────────────
  Future<void> _buscar(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    final todos = await _prodSvc.obtenerTodos();
    final q = query.toLowerCase();
    _resultados = todos.where((p) {
      return p.descripcion.toLowerCase().contains(q) ||
          p.codigo.toLowerCase().contains(q) ||
          p.marca.toLowerCase().contains(q);
    }).take(20).toList();
    if (!mounted) return;
    setState(() => _buscando = false);
  }

  void _agregarAlCarrito(Producto p) {
    final idx = _carrito.indexWhere((i) => i.producto.id == p.id);
    if (idx >= 0) {
      _carrito[idx].cantidad++;
    } else {
      _carrito.add(_ItemCarrito(producto: p));
    }
    _busquedaCtrl.clear();
    setState(() => _resultados = []);
  }

  void _quitarDelCarrito(int index) {
    setState(() => _carrito.removeAt(index));
  }

  // ── Cálculos ───────────────────────────────────────────────────────────────
  double get _subtotal =>
      _carrito.fold(0, (sum, i) => sum + i.subtotal);

  double get _descuento {
    final pct = double.tryParse(_descCtrl.text) ?? 0;
    return _subtotal * pct / 100;
  }

  double get _baseImponible => _subtotal - _descuento;

  double get _iva {
    // Factura A: IVA 21% sobre base imponible (discriminado)
    // Factura B y C: sin IVA discriminado (ya incluido en precio)
    return widget.tipo == 'factura_a' ? _baseImponible * 0.21 : 0;
  }

  double get _total => _baseImponible + _iva;

  // ── Guardar ────────────────────────────────────────────────────────────────
  Future<void> _finalizar() async {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío')),
      );
      return;
    }
    if (widget.tipo == 'factura_a' &&
        (_clienteSeleccionado == null ||
            _clienteSeleccionado!.cuit.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura A requiere cliente con CUIT cargado'),
        ),
      );
      return;
    }
    setState(() => _finalizando = true);
    try {
      final numero = await _ventaSvc.siguienteNumero(widget.tipo);
      final venta = Venta(
        tipo: widget.tipo,
        numero: numero,
        clienteId: _clienteSeleccionado?.id,
        fecha: DateTime.now(),
        subtotal: _subtotal,
        descuento: _descuento,
        iva: _iva,
        total: _total,
        estado: 'confirmada',
        estadoPago: 'pendiente',
        observaciones: _obsCtrl.text.trim(),
      );
      final items = _carrito
          .map(
            (i) => VentaItem(
              ventaId: 0,
              productoId: i.producto.id!,
              productoDescripcion: i.producto.descripcion,
              cantidad: i.cantidad,
              precio: i.precioUnitario,
              subtotal: i.subtotal,
            ),
          )
          .toList();
      await _ventaSvc.crear(venta, items);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$numero guardada correctamente')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  String get _titulo {
    switch (widget.tipo) {
      case 'factura_a':
        return 'Factura A';
      case 'factura_b':
        return 'Factura B';
      case 'factura_c':
        return 'Factura C';
      default:
        return 'Venta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _modoLectura
              ? '${_ventaExistente?.tipoLabel ?? _titulo}  '
                  '${_ventaExistente?.numero ?? ''}'
              : 'Nueva $_titulo',
        ),
        actions: [
          if (_modoLectura && _ventaExistente != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'anular') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Anular venta'),
                      content: const Text('¿Confirmar anulación?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Anular'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _ventaSvc.anular(_ventaExistente!.id!);
                    if (!mounted) return;
                    Navigator.pop(context);
                  }
                } else if (action == 'cobrado' ||
                    action == 'parcial' ||
                    action == 'pendiente') {
                  await _ventaSvc.actualizarEstadoPago(
                    _ventaExistente!.id!,
                    action,
                  );
                  await _cargarVentaExistente();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'cobrado',
                  child: Text('Marcar como cobrado'),
                ),
                const PopupMenuItem(
                  value: 'parcial',
                  child: Text('Marcar como pago parcial'),
                ),
                const PopupMenuItem(
                  value: 'pendiente',
                  child: Text('Marcar como pendiente'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'anular',
                  child: Text(
                    'Anular',
                    style: TextStyle(color: AppVisuals.danger(cs)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Cliente selector
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<Cliente>(
              initialValue: _clienteSeleccionado,
              decoration: InputDecoration(
                labelText: widget.tipo == 'factura_a'
                    ? 'Cliente (requerido para FA)'
                    : 'Cliente (opcional)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin cliente')),
                ..._clientes.map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                      '${c.nombreCompleto}${c.cuit.isNotEmpty ? ' — ${c.cuit}' : ''}',
                    ),
                  ),
                ),
              ],
              onChanged:
                  _modoLectura ? null : (v) => setState(() => _clienteSeleccionado = v),
            ),
          ),
          if (!_modoLectura) ...[
            // Descuento
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descuento (%)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: '%',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            // Búsqueda de productos
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _busquedaCtrl,
                decoration: const InputDecoration(
                  hintText: 'Buscar producto por nombre o código...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _buscar,
              ),
            ),
            if (_buscando)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              )
            else if (_resultados.isNotEmpty)
              SizedBox(
                height: 180,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _resultados.length,
                  itemBuilder: (_, i) {
                    final p = _resultados[i];
                    return ListTile(
                      dense: true,
                      title: Text(p.descripcion),
                      subtitle: Text('Precio: \$${p.precio.toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_rounded),
                        onPressed: () => _agregarAlCarrito(p),
                      ),
                    );
                  },
                ),
              ),
          ],
          const Divider(height: 1),
          // Carrito
          Expanded(
            child: _carrito.isEmpty
                ? const Center(child: Text('Sin productos'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _carrito.length,
                    itemBuilder: (_, i) {
                      final item = _carrito[i];
                      return Card(
                        child: ListTile(
                          dense: true,
                          title: Text(item.producto.descripcion),
                          subtitle: Text(
                            '\$${item.precioUnitario.toStringAsFixed(2)} × ${item.cantidad}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!_modoLectura) ...[
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (item.cantidad > 1) {
                                      setState(() => item.cantidad--);
                                    } else {
                                      _quitarDelCarrito(i);
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () =>
                                      setState(() => item.cantidad++),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Totales
          Container(
            padding: const EdgeInsets.all(12),
            color: cs.surfaceContainerHighest,
            child: Column(
              children: [
                _filaTotal('Subtotal', _subtotal),
                if (_descuento > 0)
                  _filaTotal(
                    'Descuento (${_descCtrl.text}%)',
                    -_descuento,
                    color: AppVisuals.success(cs),
                  ),
                if (widget.tipo == 'factura_a')
                  _filaTotal('IVA 21%', _iva),
                const Divider(),
                _filaTotal('TOTAL', _total, bold: true, fontSize: 18),
                if (!_modoLectura)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _finalizando ? null : _finalizar,
                        icon: _finalizando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded),
                        label: Text('Confirmar $_titulo'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTotal(
    String label,
    double monto, {
    Color? color,
    bool bold = false,
    double fontSize = 14,
  }) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            '\$${monto.toStringAsFixed(2)}',
            style: style,
          ),
        ],
      ),
    );
  }
}
