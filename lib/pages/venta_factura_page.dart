import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/cliente.dart';
import '../models/pago.dart';
import '../models/producto.dart';
import '../models/venta.dart';
import '../models/venta_item.dart';
import '../services/cliente_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../services/venta_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cobrar_dialog.dart';

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
  final TextEditingController _abonadoCtrl = TextEditingController(text: '0');

  List<Producto> _resultados = [];
  final List<_ItemCarrito> _carrito = [];
  List<Cliente> _clientes = [];
  List<Pago> _pagos = [];
  Cliente? _clienteSeleccionado;
  String _medioPago = 'efectivo';

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
    _abonadoCtrl.dispose();
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
    final pagos = await CuentaCorrienteService().pagosDeVenta(widget.ventaId!);
    if (!mounted) return;
    setState(() {
      _ventaExistente = venta;
      _modoLectura = true;
      _pagos = pagos;
      _obsCtrl.text = venta.observaciones;
      _descCtrl.text = venta.descuento.toStringAsFixed(2);
      _abonadoCtrl.text = venta.totalPagado.toStringAsFixed(2);
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

  double get _montoAbonado {
    final v = double.tryParse(_abonadoCtrl.text.replaceAll(',', '.')) ?? 0;
    return v.clamp(0, _total).toDouble();
  }

  double get _saldoPendiente =>
      (_total - _montoAbonado).clamp(0, _total).toDouble();

  String get _estadoPagoPreview =>
      Venta.calcularEstadoPago(_total, _montoAbonado);

  bool get _requiereCliente =>
      widget.tipo == 'factura_a' ||
      widget.tipo == 'factura_b' ||
      widget.tipo == 'factura_c' ||
      widget.tipo == 'nota_entrega';

  // ── Guardar ────────────────────────────────────────────────────────────────
  Future<void> _finalizar() async {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío')),
      );
      return;
    }
    if (_requiereCliente && _clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un cliente')),
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
      final abonado = _montoAbonado;
      final venta = Venta(
        tipo: widget.tipo,
        numero: numero,
        clienteId: _clienteSeleccionado?.id,
        fecha: DateTime.now(),
        subtotal: _subtotal,
        descuento: _descuento,
        iva: _iva,
        total: _total,
        totalPagado: abonado,
        saldoPendiente: _saldoPendiente,
        estado: 'confirmada',
        estadoPago: _estadoPagoPreview,
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
      await _ventaSvc.crear(
        venta,
        items,
        montoAbonado: abonado,
        medioPago: _medioPago,
      );
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

  Future<Map<String, dynamic>> _mapaVentaPdf() async {
    final venta = _ventaExistente!;
    return {
      'numero': venta.numero,
      'fecha': venta.fecha.toIso8601String(),
      'total': venta.total,
      'descuento': venta.descuento,
      'estadoPago': venta.estadoPago,
      'observaciones': venta.observaciones,
    };
  }

  Future<List<Map<String, dynamic>>> _itemsVentaPdf() async {
    if (_modoLectura && _ventaExistente?.id != null) {
      final items = await _ventaSvc.obtenerItems(_ventaExistente!.id!);
      return items
          .map(
            (i) => {
              'descripcion': i.productoDescripcion,
              'cantidad': i.cantidad,
              'precioUnitario': i.precio,
              'subtotal': i.subtotal,
            },
          )
          .toList();
    }
    return _carrito
        .map(
          (i) => {
            'descripcion': i.producto.descripcion,
            'cantidad': i.cantidad,
            'precioUnitario': i.precioUnitario,
            'subtotal': i.subtotal,
          },
        )
        .toList();
  }

  Future<void> _imprimirPdf() async {
    if (_ventaExistente == null) return;
    final pdfService = PdfService();
    final items = await _itemsVentaPdf();
    final bytes = await pdfService.generateFacturaPdf(
      await _mapaVentaPdf(),
      items,
      _clienteSeleccionado?.nombre ?? 'Consumidor final',
      clienteDireccion: _clienteSeleccionado?.direccion,
      clienteTelefono: _clienteSeleccionado?.telefono,
      tipoDocumento: _tipoDocumentoPdf,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _compartirPdf() async {
    if (_ventaExistente == null) return;
    final pdfService = PdfService();
    final items = await _itemsVentaPdf();
    final bytes = await pdfService.generateFacturaPdf(
      await _mapaVentaPdf(),
      items,
      _clienteSeleccionado?.nombre ?? 'Consumidor final',
      clienteDireccion: _clienteSeleccionado?.direccion,
      clienteTelefono: _clienteSeleccionado?.telefono,
      tipoDocumento: _tipoDocumentoPdf,
    );
    final file = await pdfService.guardarPdf(
      bytes,
      '${_ventaExistente!.numero}.pdf',
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: _ventaExistente!.numero),
    );
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
      case 'presupuesto':
        return 'Presupuesto';
      case 'nota_entrega':
        return 'Nota de entrega';
      default:
        return 'Venta';
    }
  }

  String get _tipoDocumentoPdf {
    switch (widget.tipo) {
      case 'factura_a':
        return 'FACTURA A';
      case 'factura_b':
        return 'FACTURA B';
      case 'factura_c':
        return 'FACTURA C';
      case 'presupuesto':
        return 'PRESUPUESTO';
      case 'nota_entrega':
        return 'NOTA DE ENTREGA';
      default:
        return _titulo.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: _modoLectura
            ? '${_ventaExistente?.tipoLabel ?? _titulo}  '
                '${_ventaExistente?.numero ?? ''}'
            : 'Nueva $_titulo',
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
                } else if (action == 'imprimir') {
                  await _imprimirPdf();
                } else if (action == 'compartir') {
                  await _compartirPdf();
                } else if (action == 'cobrar') {
                  final ok = await mostrarDialogoCobrar(
                    context: context,
                    venta: _ventaExistente!,
                  );
                  if (ok) await _cargarVentaExistente();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'imprimir',
                  child: Text('Imprimir PDF'),
                ),
                const PopupMenuItem(
                  value: 'compartir',
                  child: Text('Compartir PDF'),
                ),
                if ((_ventaExistente?.saldoPendiente ?? 0) > 0.009) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'cobrar',
                    child: Text('Cobrar'),
                  ),
                ],
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
              key: ValueKey(_clienteSeleccionado?.id),
              initialValue: _clienteSeleccionado,
              decoration: InputDecoration(
                labelText: _requiereCliente
                    ? 'Cliente (obligatorio)'
                    : 'Cliente (opcional)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                if (!_requiereCliente)
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin cliente'),
                  ),
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
                if (!_modoLectura) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _abonadoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Monto abonado',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixText: '\$ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_medioPago),
                          initialValue: _medioPago,
                          decoration: const InputDecoration(
                            labelText: 'Medio de pago',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: Pago.mediosPago
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(Pago.labelMedio(m)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _medioPago = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _filaTotal(
                          'Saldo pendiente',
                          _saldoPendiente,
                          color: colorEstadoPago(_estadoPagoPreview, cs),
                        ),
                      ),
                      chipEstadoPago(_estadoPagoPreview, cs),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          _abonadoCtrl.text = '0';
                          setState(() {});
                        },
                        child: const Text('No pagar'),
                      ),
                      TextButton(
                        onPressed: () {
                          _abonadoCtrl.text = (_total / 2).toStringAsFixed(2);
                          setState(() {});
                        },
                        child: const Text('Mitad'),
                      ),
                      TextButton(
                        onPressed: () {
                          _abonadoCtrl.text = _total.toStringAsFixed(2);
                          setState(() {});
                        },
                        child: const Text('Total'),
                      ),
                    ],
                  ),
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
                ] else if (_ventaExistente != null) ...[
                  _filaTotal('Pagado', _ventaExistente!.totalPagado),
                  _filaTotal(
                    'Saldo pendiente',
                    _ventaExistente!.saldoPendiente,
                    color: colorEstadoPago(_ventaExistente!.estadoPago, cs),
                  ),
                  chipEstadoPago(_ventaExistente!.estadoPago, cs),
                  if (_pagos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pagos (${_pagos.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ..._pagos.take(3).map(
                          (p) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${p.fecha.day.toString().padLeft(2, '0')}/'
                              '${p.fecha.month.toString().padLeft(2, '0')} · '
                              '\$${p.monto.toStringAsFixed(2)} · '
                              '${Pago.labelMedio(p.medioPago)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                  ],
                  if (_ventaExistente!.saldoPendiente > 0.009)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final ok = await mostrarDialogoCobrar(
                              context: context,
                              venta: _ventaExistente!,
                            );
                            if (ok) await _cargarVentaExistente();
                          },
                          icon: const Icon(Icons.payments_rounded),
                          label: const Text('Cobrar'),
                        ),
                      ),
                    ),
                ],
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
