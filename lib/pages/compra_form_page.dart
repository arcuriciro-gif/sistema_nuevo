import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/compra_detalle.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../core/config/platform_capabilities.dart';
import '../core/utils/busqueda_texto.dart';
import '../services/compra_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import '../theme/module_app_bar.dart';
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
  final int? compraId;

  const CompraFormPage({super.key, this.compraId});

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
  String? _numeroExistente;
  bool cargando = true;
  bool guardando = false;

  bool get _esEdicion => widget.compraId != null;

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

    if (_esEdicion) {
      final compraId = widget.compraId!;
      final compras = await compraService.obtenerTodasConProveedor();
      Map<String, dynamic>? compra;
      for (final c in compras) {
        if ((c['id'] as num?)?.toInt() == compraId) {
          compra = c;
          break;
        }
      }
      if (compra != null) {
        _numeroExistente = compra['numero']?.toString();
        observacionesController.text =
            compra['observaciones']?.toString() ?? '';
        final pid = (compra['proveedorId'] as num?)?.toInt();
        if (pid != null) {
          for (final p in proveedores) {
            if (p.id == pid) {
              proveedorSeleccionado = p;
              break;
            }
          }
        }
        final rows = await compraService.obtenerItems(compraId);
        items = [];
        for (final row in rows) {
          final productoId = (row['productoId'] as num?)?.toInt();
          Producto? prod;
          if (productoId != null) {
            for (final p in productos) {
              if (p.id == productoId) {
                prod = p;
                break;
              }
            }
          }
          prod ??= Producto(
            id: productoId,
            codigo: row['codigo']?.toString() ?? '',
            descripcion:
                row['productoDescripcion']?.toString() ?? 'Producto',
            marca: row['marca']?.toString() ?? '',
            categoria: '',
            proveedor: '',
            ubicacion: '',
            stock: 0,
            costo: (row['costo'] as num?)?.toDouble() ?? 0,
            precio: 0,
            observaciones: '',
            foto: '',
          );
          items.add(
            _ItemCompra(
              producto: prod,
              cantidad: (row['cantidad'] as num?)?.toInt() ?? 1,
              costo: (row['costo'] as num?)?.toDouble() ?? prod.costo,
            ),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() => cargando = false);
  }

  Future<String?> _abrirScanner() async {
    if (PlatformCapabilities.isWindowsDesktop) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner de cámara no está disponible en Windows.'),
        ),
      );
      return null;
    }
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
  }

  void _filtrarProductos(String texto) {
    productosFiltrados = productos
        .where(
          (p) => BusquedaTexto.coincide(texto, [
            p.descripcion,
            p.codigo,
            p.codigoBarras,
            p.marca,
            p.modelo,
            p.colorProducto,
            p.talle,
          ]),
        )
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
      final detalles = <CompraDetalle>[];
      for (final i in items) {
        final pid = i.producto.id;
        if (pid == null) {
          throw StateError(
            'Producto sin id: ${i.producto.descripcion}. Volvé a elegirlo.',
          );
        }
        detalles.add(
          CompraDetalle(
            compraId: widget.compraId ?? 0,
            productoId: pid,
            productoDescripcion: i.producto.descripcion,
            cantidad: i.cantidad,
            costo: i.costo,
            subtotal: i.subtotal,
          ),
        );
      }

      if (_esEdicion) {
        final compra = Compra(
          id: widget.compraId,
          proveedorId: proveedorSeleccionado?.id,
          proveedorNombre: proveedorSeleccionado?.nombre ?? 'Sin proveedor',
          numero: _numeroExistente ?? '',
          fecha: DateTime.now(),
          total: total,
          observaciones: observacionesController.text.trim(),
          estado: 'confirmada',
        );
        await compraService.actualizar(widget.compraId!, compra, detalles);
      } else {
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
        await compraService.insertar(compra, detalles);
      }

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
      appBar: buildModuleAppBar(
        context,
        title: _esEdicion ? 'Editar compra' : 'Nueva Compra',
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
                                  '\$${item.costo.toStringAsFixed(2)} c/u · '
                                  'Stock: ${item.producto.stock}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Menos',
                                      icon: const Icon(Icons.remove_rounded),
                                      onPressed: () {
                                        setState(() {
                                          if (item.cantidad <= 1) {
                                            items.removeAt(idx);
                                          } else {
                                            items[idx] = _ItemCompra(
                                              producto: item.producto,
                                              cantidad: item.cantidad - 1,
                                              costo: item.costo,
                                            );
                                          }
                                        });
                                      },
                                    ),
                                    Text(
                                      '${item.cantidad}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Más',
                                      icon: const Icon(Icons.add_rounded),
                                      onPressed: () {
                                        setState(() {
                                          items[idx] = _ItemCompra(
                                            producto: item.producto,
                                            cantidad: item.cantidad + 1,
                                            costo: item.costo,
                                          );
                                        });
                                      },
                                    ),
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
                  child: SafeArea(
                    top: false,
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
                          label: Text(
                            _esEdicion ? 'GUARDAR CAMBIOS' : 'GUARDAR COMPRA',
                          ),
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
