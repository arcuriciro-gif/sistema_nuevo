import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pedido.dart';
import '../models/pedido_item.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/pedido_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/form_save_bar.dart';

class _LineaPedido {
  final TextEditingController articulo;
  final TextEditingController cantidad;
  final TextEditingController color;
  final TextEditingController observaciones;
  int? productoId;

  _LineaPedido({
    String articulo = '',
    int cantidad = 1,
    String color = '',
    String observaciones = '',
    this.productoId,
  })  : articulo = TextEditingController(text: articulo),
        cantidad = TextEditingController(text: '$cantidad'),
        color = TextEditingController(text: color),
        observaciones = TextEditingController(text: observaciones);

  void dispose() {
    articulo.dispose();
    cantidad.dispose();
    color.dispose();
    observaciones.dispose();
  }

  PedidoItem toItem(int pedidoId, int orden) {
    return PedidoItem(
      pedidoId: pedidoId,
      productoId: productoId,
      articulo: articulo.text.trim(),
      cantidad: int.tryParse(cantidad.text.trim()) ?? 1,
      color: color.text.trim(),
      observaciones: observaciones.text.trim(),
      orden: orden,
    );
  }
}

class PedidoFormPage extends StatefulWidget {
  final int? pedidoId;
  final Proveedor? proveedorInicial;
  final List<PedidoItem>? lineasIniciales;

  const PedidoFormPage({
    super.key,
    this.pedidoId,
    this.proveedorInicial,
    this.lineasIniciales,
  });

  @override
  State<PedidoFormPage> createState() => _PedidoFormPageState();
}

class _PedidoFormPageState extends State<PedidoFormPage> {
  final _pedidoService = PedidoService();
  final _proveedorService = ProveedorService();
  final _productoService = ProductoService();
  final _obsCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();

  Pedido? _pedido;
  Proveedor? _proveedor;
  List<_LineaPedido> _lineas = [];
  List<Producto> _productos = [];
  String _estado = 'borrador';
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    _buscarCtrl.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    await _pedidoService.asegurarProveedoresPlanilla();
    final productos = await _productoService.obtenerTodos();
    Proveedor? proveedor = widget.proveedorInicial;

    if (widget.pedidoId != null) {
      final pedido = await _pedidoService.obtenerPorId(widget.pedidoId!);
      final items = await _pedidoService.obtenerItems(widget.pedidoId!);
      if (pedido != null) {
        _pedido = pedido;
        _estado = pedido.estado;
        _obsCtrl.text = pedido.observaciones;
        if (pedido.proveedorId != null) {
          proveedor = await _proveedorService.obtenerPorId(pedido.proveedorId!);
        }
        proveedor ??= Proveedor(
          nombre: pedido.proveedorNombre,
          telefono: '',
          email: '',
          observaciones: '',
        );
        _lineas = items
            .map(
              (i) => _LineaPedido(
                articulo: i.articulo,
                cantidad: i.cantidad,
                color: i.color,
                observaciones: i.observaciones,
                productoId: i.productoId,
              ),
            )
            .toList();
      }
    }

    if (proveedor != null && proveedor.id == null) {
      final todos = await _proveedorService.obtenerTodos();
      proveedor = todos.cast<Proveedor?>().firstWhere(
            (p) =>
                p!.nombre.trim().toLowerCase() ==
                proveedor!.nombre.trim().toLowerCase(),
            orElse: () => proveedor,
          );
    }

    if (_lineas.isEmpty &&
        widget.lineasIniciales != null &&
        widget.lineasIniciales!.isNotEmpty) {
      _lineas = widget.lineasIniciales!
          .map(
            (i) => _LineaPedido(
              articulo: i.articulo,
              cantidad: i.cantidad,
              color: i.color,
              observaciones: i.observaciones,
              productoId: i.productoId,
            ),
          )
          .toList();
      if (_obsCtrl.text.trim().isEmpty) {
        _obsCtrl.text = 'Generado desde pedido sugerido';
      }
    }

    if (_lineas.isEmpty) {
      _lineas = [_LineaPedido()];
    }

    if (!mounted) return;
    setState(() {
      _proveedor = proveedor;
      _productos = productos;
      _cargando = false;
    });
  }

  void _agregarLinea({Producto? producto}) {
    setState(() {
      _lineas.add(
        _LineaPedido(
          articulo: producto?.descripcion ?? '',
          productoId: producto?.id,
          color: producto?.colorProducto ?? '',
        ),
      );
    });
  }

  void _quitarLinea(int index) {
    if (_lineas.length <= 1) {
      setState(() {
        _lineas[0].articulo.clear();
        _lineas[0].cantidad.text = '1';
        _lineas[0].color.clear();
        _lineas[0].observaciones.clear();
        _lineas[0].productoId = null;
      });
      return;
    }
    setState(() {
      _lineas.removeAt(index).dispose();
    });
  }

  Future<void> _buscarYAgregarProducto() async {
    final q = _buscarCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return;
    final matches = _productos
        .where(
          (p) =>
              p.descripcion.toLowerCase().contains(q) ||
              p.codigo.toLowerCase().contains(q) ||
              p.codigoBarras.toLowerCase().contains(q),
        )
        .take(20)
        .toList();
    if (!mounted) return;
    if (matches.isEmpty) {
      _agregarLinea();
      _lineas.last.articulo.text = _buscarCtrl.text.trim();
      _buscarCtrl.clear();
      setState(() {});
      return;
    }
    final elegido = await showModalBottomSheet<Producto>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: matches
              .map(
                (p) => ListTile(
                  title: Text(p.descripcion),
                  subtitle: Text('${p.codigo} · stock ${p.stock}'),
                  onTap: () => Navigator.pop(ctx, p),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (elegido != null) {
      _agregarLinea(producto: elegido);
      _buscarCtrl.clear();
    }
  }

  Future<void> _guardar({String? nuevoEstado}) async {
    if (_proveedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí un proveedor')),
      );
      return;
    }
    final items = <PedidoItem>[];
    for (var i = 0; i < _lineas.length; i++) {
      final linea = _lineas[i];
      if (linea.articulo.text.trim().isEmpty) continue;
      items.add(linea.toItem(_pedido?.id ?? 0, i));
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos un artículo')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      var proveedor = _proveedor!;
      if (proveedor.id == null) {
        final id = await _proveedorService.insertar(
          Proveedor(
            nombre: proveedor.nombre,
            telefono: '',
            email: '',
            observaciones: 'Proveedor de planilla de pedidos',
          ),
        );
        proveedor = proveedor.copyWith(id: id);
      }

      final estado = nuevoEstado ?? _estado;
      final pedido = Pedido(
        id: _pedido?.id,
        proveedorId: proveedor.id,
        proveedorNombre: proveedor.nombre,
        numero: _pedido?.numero ?? '',
        fecha: _pedido?.fecha ?? DateTime.now(),
        observaciones: _obsCtrl.text.trim(),
        estado: estado,
        fechaCreacion: _pedido?.fechaCreacion,
      );
      final id = await _pedidoService.guardar(pedido, items);
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _proveedor = proveedor;
      });
      // Recargar número generado
      final guardado = await _pedidoService.obtenerPorId(id);
      if (guardado != null && mounted) {
        setState(() => _pedido = guardado);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${guardado?.numero ?? ''} guardado',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = _pedido?.numero.isNotEmpty == true
        ? 'Pedido ${_pedido!.numero}'
        : 'Nuevo pedido';

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: titulo,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _guardar(nuevoEstado: v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'borrador', child: Text('Marcar borrador')),
              PopupMenuItem(value: 'enviado', child: Text('Marcar enviado')),
              PopupMenuItem(value: 'cerrado', child: Text('Marcar cerrado')),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                FormSaveBar(
                  loading: _guardando,
                  onPressed: _guardando ? null : () => _guardar(),
                  label: 'Guardar pedido',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_shipping_rounded),
                        title: Text(
                          _proveedor?.nombre ?? 'Sin proveedor',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('Estado: $_estado'),
                      ),
                      TextField(
                        controller: _obsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones del pedido',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _buscarCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Buscar producto o escribir artículo',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                              onSubmitted: (_) => _buscarYAgregarProducto(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Agregar',
                            onPressed: _buscarYAgregarProducto,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Líneas: artículo, cantidad, color, observaciones',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_lineas.length, (index) {
                        final linea = _lineas[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${index + 1}',
                                      style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Quitar',
                                      onPressed: () => _quitarLinea(index),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ),
                                TextField(
                                  controller: linea.articulo,
                                  decoration: const InputDecoration(
                                    labelText: 'Artículo',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        controller: linea.cantidad,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Cant.',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: linea.color,
                                        decoration: const InputDecoration(
                                          labelText: 'Color',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: linea.observaciones,
                                  decoration: const InputDecoration(
                                    labelText: 'Observaciones',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: () => _agregarLinea(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Agregar artículo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
