import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/utils/busqueda_texto.dart';
import '../models/producto.dart';
import '../models/remito.dart';
import '../models/remito_detalle.dart';
import '../services/cliente_service.dart';
import '../services/documento_cliente_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import 'scanner_page.dart';

// ---------------------------------------------------------------------------
// Ítem del carrito
// ---------------------------------------------------------------------------
class _ItemCarrito {
  final Producto producto;
  int cantidad;
  double precioUnitario;

  _ItemCarrito({required this.producto})
      : cantidad = 1, precioUnitario = producto.precio;

  double get subtotal => cantidad * precioUnitario;
}

// ---------------------------------------------------------------------------
// Página principal
// ---------------------------------------------------------------------------
class VentaRapidaPage extends StatefulWidget {
  const VentaRapidaPage({super.key});

  @override
  State<VentaRapidaPage> createState() => _VentaRapidaPageState();
}

class _VentaRapidaPageState extends State<VentaRapidaPage> {
  final ProductoService _prodSvc = ProductoService();
  final RemitoService _remitoSvc = RemitoService();
  final ClienteService _clienteSvc = ClienteService();

  final TextEditingController _busquedaCtrl = TextEditingController();

  List<Producto> _resultados = [];
  final List<_ItemCarrito> _carrito = [];
  bool _buscando = false;
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
  }

  void _onDatosActualizados() {
    if (!mounted || _busquedaCtrl.text.trim().isEmpty) return;
    _buscar(_busquedaCtrl.text);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Búsqueda
  // ---------------------------------------------------------------------------
  Future<void> _buscar(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    // Match exacto por código de barras primero (escáner)
    final porBarras = await _prodSvc.buscarPorCodigoBarras(query.trim());
    if (porBarras != null) {
      if (!mounted) return;
      setState(() {
        _resultados = [porBarras];
        _buscando = false;
      });
      // Si es match exacto de barras, agregar directo
      if (porBarras.codigoBarras == query.trim() ||
          porBarras.codigo == query.trim()) {
        _agregarAlCarrito(porBarras);
        return;
      }
    }
    final todos = await _prodSvc.obtenerTodos();
    final filtrados = todos
        .where(
          (p) => BusquedaTexto.coincide(query, [
            p.descripcion,
            p.codigo,
            p.codigoBarras,
            p.marca,
            p.modelo,
            p.colorProducto,
            p.talle,
          ]),
        )
        .take(40)
        .toList();
    if (!mounted) return;
    setState(() {
      _resultados = filtrados;
      _buscando = false;
    });
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || codigo.trim().isEmpty || !mounted) return;
    _busquedaCtrl.text = codigo.trim();
    await _buscar(codigo.trim());
  }

  // ---------------------------------------------------------------------------
  // Carrito
  // ---------------------------------------------------------------------------
  void _agregarAlCarrito(Producto producto) {
    final idx = _carrito.indexWhere((e) => e.producto.id == producto.id);
    setState(() {
      if (idx >= 0) {
        _carrito[idx].cantidad++;
      } else {
        _carrito.add(_ItemCarrito(producto: producto));
      }
      _resultados = [];
      _busquedaCtrl.clear();
    });
  }

  void _cambiarCantidad(int idx, int delta) {
    setState(() {
      _carrito[idx].cantidad += delta;
      if (_carrito[idx].cantidad <= 0) {
        _carrito.removeAt(idx);
      }
    });
  }

  void _eliminarItem(int idx) {
    setState(() => _carrito.removeAt(idx));
  }

  void _editarPrecio(int idx) async {
    final ctrl = TextEditingController(
      text: _carrito[idx].precioUnitario.toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Precio - ${_carrito[idx].producto.descripcion}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '\$',
            labelText: 'Precio unitario',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) {
      final nuevo = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (nuevo != null && nuevo >= 0) {
        setState(() => _carrito[idx].precioUnitario = nuevo);
      }
    }
  }

  double get _total => _carrito.fold(0, (s, e) => s + e.subtotal);

  // ---------------------------------------------------------------------------
  // Finalizar venta
  // ---------------------------------------------------------------------------
  Future<void> _finalizarVenta() async {
    if (_carrito.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: \$${_total.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text('${_carrito.length} productos'),
            const SizedBox(height: 8),
            const Text(
              'Se generará un remito a nombre de MOSTRADOR y se descontará el stock.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _finalizando = true);

    try {
      final mostrador = await _clienteSvc.obtenerOCrearMostrador();
      final numero = await _remitoSvc.generarNumero();

      final remito = Remito(
        numero: numero,
        fecha: DateTime.now(),
        tipo: 'salida',
        clienteId: mostrador.id?.toString(),
        estado: 'confirmado',
        estadoPago: 'pendiente',
        observaciones: 'Venta rápida en mostrador',
        total: _total,
      );

      final items = _carrito
          .map(
            (e) => RemitoDetalle(
              remitoId: 0,
              productoId: e.producto.id!,
              cantidad: e.cantidad,
              precioUnitario: e.precioUnitario,
              subtotal: e.subtotal,
              costoUnitario: e.producto.costo,
            ),
          )
          .toList();

      final remitoId = await _remitoSvc.insertar(remito, items);
      final totalVenta = remito.total;
      final carritoSnapshot = List<_ItemCarrito>.from(_carrito);

      // Archivar PDF para enviarlo luego desde el celular
      try {
        final pdfSvc = PdfService();
        final remitoMap = {
          'id': remitoId,
          'numero': numero,
          'fecha': remito.fecha.toIso8601String(),
          'total': remito.total,
          'descuento': 0,
        };
        final itemsPdf = carritoSnapshot
            .map(
              (e) => {
                'descripcion': e.producto.descripcion,
                'cantidad': e.cantidad,
                'precio': e.precioUnitario,
                'subtotal': e.subtotal,
              },
            )
            .toList();
        final bytes = await pdfSvc.generateRemitoPdf(
          remitoMap,
          itemsPdf,
          mostrador.nombre,
        );
        if (bytes.isNotEmpty) {
          final archivo = await pdfSvc.guardarPdf(bytes, 'remito_$numero.pdf');
          await DocumentoClienteService.instance.archivarPdf(
            archivo: archivo,
            tipo: 'remito',
            numero: numero,
            clienteNombre: mostrador.nombre,
            clienteId: mostrador.id,
            clienteSyncId: mostrador.syncId,
          );
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _carrito.clear();
        _finalizando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Venta registrada · Remito $numero · Total \$${totalVenta.toStringAsFixed(2)}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _finalizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar la venta: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Venta rápida',
        actions: [
          if (_carrito.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.shopping_cart_rounded, size: 16),
                  label: Text('${_carrito.length} ítems'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // --- Barra de búsqueda ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busquedaCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Código, barras, descripción o marca...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Escanear código',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: _escanear,
                    ),
                    if (_busquedaCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() => _resultados = []);
                        },
                      ),
                  ],
                ),
              ),
              onChanged: _buscar,
            ),
          ),

          // --- Resultados de búsqueda ---
          if (_buscando)
            const LinearProgressIndicator()
          else if (_resultados.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _resultados.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = _resultados[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      child: Text(
                        p.descripcion.isNotEmpty
                            ? p.descripcion[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    title: Text(p.descripcion,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${p.codigo} · ${p.marca} · Stock: ${p.stock}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      '\$${p.precio.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    onTap: () => _agregarAlCarrito(p),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          // --- Carrito ---
          Expanded(
            child: _carrito.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(alpha: .3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'El carrito está vacío',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: .5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Buscá un producto para agregar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: .4),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _carrito.length,
                    itemBuilder: (_, i) {
                      final item = _carrito[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // Info producto
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.producto.descripcion,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      item.producto.codigo,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    GestureDetector(
                                      onTap: () => _editarPrecio(i),
                                      child: Row(
                                        children: [
                                          Text(
                                            '\$${item.precioUnitario.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit_rounded,
                                            size: 12,
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: .6),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Controles cantidad
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_rounded,
                                        size: 18),
                                    onPressed: () =>
                                        _cambiarCantidad(i, -1),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                  ),
                                  Container(
                                    width: 36,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${item.cantidad}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_rounded,
                                        size: 18),
                                    onPressed: () =>
                                        _cambiarCantidad(i, 1),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                  ),
                                ],
                              ),
                              // Subtotal
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '\$${item.subtotal.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              // Eliminar
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                onPressed: () => _eliminarItem(i),
                                color: theme.colorScheme.error
                                    .withValues(alpha: .7),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // --- Total y botón finalizar ---
          if (_carrito.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        '\$${_total.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _finalizando
                      ? const CircularProgressIndicator()
                      : FilledButton.icon(
                          onPressed: _finalizarVenta,
                          icon: const Icon(Icons.point_of_sale_rounded),
                          label: const Text('Finalizar venta'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(160, 48),
                          ),
                        ),
                ],
              ),
            ),
            ),
        ],
      ),
    );
  }
}
