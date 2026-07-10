import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/compra_detalle.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/compra_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import 'scanner_page.dart';

class _ItemCompra {
  final Producto producto;
  int cantidad;
  double costo;

  _ItemCompra({
    required this.producto,
    required this.cantidad,
    required this.costo,
  });

  double get subtotal => cantidad * costo;
}

class CompraFormPage extends StatefulWidget {
  const CompraFormPage({super.key});

  @override
  State<CompraFormPage> createState() => _CompraFormPageState();
}

class _CompraFormPageState extends State<CompraFormPage> {
  final CompraService compraService = CompraService();
  final ProveedorService proveedorService = ProveedorService();
  final ProductoService productoService = ProductoService();

  final TextEditingController observacionesController =
      TextEditingController();
  final TextEditingController buscarProductoController =
      TextEditingController();

  List<Proveedor> proveedores = [];
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  List<_ItemCompra> items = [];

  Proveedor? proveedorSeleccionado;
  bool cargando = true;
  bool guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    observacionesController.dispose();
    buscarProductoController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    proveedores = await proveedorService.obtenerTodos();
    productos = await productoService.obtenerTodos();
    productosFiltrados = productos;
    if (!mounted) return;
    setState(() => cargando = false);
  }

  Future<String?> _abrirScanner() {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
  }

  void _filtrarProductos(String texto) {
    texto = texto.toLowerCase();
    productosFiltrados = productos
        .where((p) =>
            p.descripcion.toLowerCase().contains(texto) ||
            p.codigo.toLowerCase().contains(texto))
        .toList();
    setState(() {});
  }

  double get total => items.fold(0, (sum, i) => sum + i.subtotal);

  void _agregarItemDirecto(
    Producto producto, {
    int cantidad = 1,
    double? costo,
  }) {
    final yaExiste = items.indexWhere((it) => it.producto.id == producto.id);
    if (yaExiste >= 0) {
      setState(() {
        items[yaExiste].cantidad += cantidad;
        if (costo != null) {
          items[yaExiste].costo = costo;
        }
      });
      return;
    }

    setState(() {
      items.add(
        _ItemCompra(
          producto: producto,
          cantidad: cantidad,
          costo: costo ?? producto.costo,
        ),
      );
    });
  }

  Future<void> _agregarProducto() async {
    buscarProductoController.clear();
    productosFiltrados = productos;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (_, ctrl) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: buscarProductoController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (v) {
                          _filtrarProductos(v);
                          setModalState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Escanear código',
                      onPressed: () async {
                        final codigo = await _abrirScanner();
                        if (codigo == null || codigo.trim().isEmpty) return;
                        buscarProductoController.text = codigo;
                        _filtrarProductos(codigo);
                        setModalState(() {});
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    itemCount: productosFiltrados.length,
                    itemBuilder: (_, i) {
                      final p = productosFiltrados[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(p.descripcion),
                          subtitle: Text(
                            '${p.codigo} | Costo: \$${p.costo.toStringAsFixed(2)} | Stock: ${p.stock}',
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _agregarItemDirecto(p);
                            },
                            child: const Text('Agregar'),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _pedirCantidad(p);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pedirCantidad(Producto producto) async {
    final cantidadCtrl = TextEditingController(text: '1');
    final costoCtrl =
        TextEditingController(text: producto.costo.toStringAsFixed(2));

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(producto.descripcion),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cantidadCtrl,
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costoCtrl,
              decoration: const InputDecoration(
                labelText: 'Costo unitario',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final cantidad = int.tryParse(cantidadCtrl.text) ?? 1;
      final costo =
          double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? producto.costo;
      _agregarItemDirecto(producto, cantidad: cantidad, costo: costo);
    }
  }

  Future<void> guardar() async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos un producto')),
      );
      return;
    }

    setState(() => guardando = true);

    try {
      final numero = await compraService.generarNumero();
      final compra = Compra(
        proveedorId: proveedorSeleccionado?.id,
        proveedorNombre: proveedorSeleccionado?.nombre ?? 'Sin proveedor',
        numero: numero,
        fecha: DateTime.now(),
        total: total,
        observaciones: observacionesController.text.trim(),
        estado: 'confirmada',
      );

      final detalles = items
          .map((i) => CompraDetalle(
                compraId: 0,
                productoId: i.producto.id!,
                productoDescripcion: i.producto.descripcion,
                cantidad: i.cantidad,
                costo: i.costo,
                subtotal: i.subtotal,
              ))
          .toList();

      await compraService.insertar(compra, detalles);

      if (!mounted) return;
      setState(() => guardando = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la compra: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Compra'),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<Proveedor>(
                          initialValue: proveedorSeleccionado,
                          decoration: InputDecoration(
                            labelText: 'Proveedor',
                            prefixIcon: const Icon(Icons.local_shipping),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: proveedores
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.nombre),
                                ),
                              )
                              .toList(),
                          onChanged: (p) =>
                              setState(() => proveedorSeleccionado = p),
                          hint: const Text('Seleccionar proveedor'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Productos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Text(
                              'Sin productos aún',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ...items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Card(
                              child: ListTile(
                                title: Text(item.producto.descripcion),
                                subtitle: Text(
                                  'x${item.cantidad} × \$${item.costo.toStringAsFixed(2)}',
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
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () =>
                                          setState(() => items.removeAt(idx)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _agregarProducto,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar producto'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: observacionesController,
                          decoration: const InputDecoration(
                            labelText: 'Observaciones',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '\$${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Color(0xFFFF7A00),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: guardando ? null : guardar,
                          icon: guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: const Text('GUARDAR COMPRA'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
