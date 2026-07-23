import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/cliente.dart';
import '../models/producto.dart';
import '../models/remito.dart';
import '../models/remito_detalle.dart';
import '../core/utils/busqueda_texto.dart';
import '../services/cliente_service.dart';
import '../services/documento_cliente_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import 'scanner_page.dart';

class _ItemRemito {
  final Producto producto;
  int cantidad;
  double precioUnitario;

  _ItemRemito({
    required this.producto,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get subtotal => cantidad * precioUnitario;
}

class RemitoFormPage extends StatefulWidget {
  const RemitoFormPage({super.key});

  @override
  State<RemitoFormPage> createState() => _RemitoFormPageState();
}

class _RemitoFormPageState extends State<RemitoFormPage> {
  final RemitoService remitoService = RemitoService();
  final ClienteService clienteService = ClienteService();
  final ProductoService productoService = ProductoService();
  final PdfService pdfService = PdfService();

  final TextEditingController observacionesController = TextEditingController();
  final TextEditingController buscarProductoController = TextEditingController();

  List<Cliente> clientes = [];
  List<Producto> productos = [];
  List<Producto> productosFiltrados = [];
  List<_ItemRemito> items = [];

  Cliente? clienteSeleccionado;
  double descuento = 0;
  bool cargando = true;
  bool guardando = false;

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  @override
  void dispose() {
    observacionesController.dispose();
    buscarProductoController.dispose();
    super.dispose();
  }

  Future<void> cargarDatos() async {
    clientes = await clienteService.obtenerTodos();
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

  void filtrarProductos(String texto) {
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

  void _seleccionarCliente(Cliente? cliente) {
    setState(() {
      clienteSeleccionado = cliente;
      descuento = ((cliente?.descuento ?? 0).clamp(0.0, 100.0)).toDouble();
    });
  }

  double get total => items.fold(0, (sum, i) => sum + i.subtotal);
  double get totalConDescuento => total * (1 - descuento / 100);

  void _agregarItemDirecto(
    Producto producto, {
    int cantidad = 1,
    double? precioUnitario,
  }) {
    final yaExiste = items.indexWhere((it) => it.producto.id == producto.id);
    if (yaExiste >= 0) {
      setState(() {
        items[yaExiste].cantidad += cantidad;
        if (precioUnitario != null) {
          items[yaExiste].precioUnitario = precioUnitario;
        }
      });
      return;
    }

    setState(() {
      items.add(
        _ItemRemito(
          producto: producto,
          cantidad: cantidad,
          precioUnitario: precioUnitario ?? producto.precio,
        ),
      );
    });
  }

  Future<void> agregarProducto() async {
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
                          filtrarProductos(v);
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
                        filtrarProductos(codigo);
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
                            '${p.codigo} | \$${p.precio.toStringAsFixed(2)} | Stock: ${p.stock}',
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
    final precioCtrl =
        TextEditingController(text: producto.precio.toStringAsFixed(2));

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
              controller: precioCtrl,
              decoration: const InputDecoration(
                labelText: 'Precio unitario',
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
      final precio =
          double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? producto.precio;
      _agregarItemDirecto(
        producto,
        cantidad: cantidad,
        precioUnitario: precio,
      );
    }
  }

  Future<void> editarDescuento() async {
    final descuentoCtrl = TextEditingController(
      text: descuento.toStringAsFixed(1),
    );

    final nuevoDescuento = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar descuento'),
        content: TextField(
          controller: descuentoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Descuento (%)',
            border: OutlineInputBorder(),
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor =
                  double.tryParse(descuentoCtrl.text.replaceAll(',', '.')) ??
                      descuento;
              Navigator.pop(
                context,
                valor.clamp(0.0, 100.0).toDouble(),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevoDescuento != null) {
      setState(() => descuento = nuevoDescuento);
    }
  }

  Future<void> _imprimirOCompartirRemito(
    Remito remito,
    List<RemitoDetalle> detalles,
    int remitoId,
  ) async {
    final remitoMap = {
      'id': remitoId,
      'numero': remito.numero,
      'fecha': remito.fecha.toIso8601String(),
      'total': remito.total,
      'descuento': remito.descuento,
    };
    final itemsPdf = detalles.map((detalle) {
      final producto =
          items.firstWhere((item) => item.producto.id == detalle.productoId).producto;
      return {
        'descripcion': producto.descripcion,
        'cantidad': detalle.cantidad,
        'precio': detalle.precioUnitario,
        'subtotal': detalle.subtotal,
      };
    }).toList();

    final accion = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remito guardado'),
        content: const Text(
          'El PDF quedó archivado por cliente (disponible en el celular).\n'
          '¿Querés imprimir o compartir ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cerrar'),
            child: const Text('Cerrar'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, 'imprimir'),
            icon: const Icon(Icons.print, color: Colors.orange),
            label: const Text('Imprimir'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'compartir'),
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
          ),
        ],
      ),
    );

    final pdf = await pdfService.generateRemitoPdf(
      remitoMap,
      itemsPdf,
      clienteSeleccionado?.nombre ?? 'Sin cliente',
    );
    if (pdf.isEmpty) {
      return;
    }

    final archivo = await pdfService.guardarPdf(
      pdf,
      'remito_${remito.numero}.pdf',
    );
    await DocumentoClienteService.instance.archivarPdf(
      archivo: archivo,
      tipo: 'remito',
      numero: remito.numero,
      clienteNombre: clienteSeleccionado?.nombre ?? 'Sin cliente',
      clienteId: clienteSeleccionado?.id,
      clienteSyncId: clienteSeleccionado?.syncId,
    );

    if (accion == null || accion == 'cerrar') {
      return;
    }

    if (accion == 'imprimir') {
      await Printing.layoutPdf(onLayout: (_) async => pdf);
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(archivo.path)]),
    );
  }

  Future<void> guardar() async {
    if (clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un cliente')),
      );
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos un producto')),
      );
      return;
    }

    final hayStockInsuficiente = items.any(
      (item) => item.cantidad > item.producto.stock,
    );
    if (hayStockInsuficiente) {
      // Informativo: no bloquea. Stock 0 es válido (retiro en proveedor, etc.).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Algunos ítems superan el stock cargado. El remito se guarda igual.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() => guardando = true);

    try {
      final numero = await remitoService.generarNumero();
      final remito = Remito(
        numero: numero,
        fecha: DateTime.now(),
        tipo: 'salida',
        clienteId: clienteSeleccionado!.id.toString(),
        estado: 'confirmado',
        estadoPago: 'pendiente',
        observaciones: observacionesController.text.trim(),
        total: totalConDescuento,
        descuento: descuento,
      );

      final detalles = items
          .map((i) => RemitoDetalle(
                remitoId: 0,
                productoId: i.producto.id!,
                cantidad: i.cantidad,
                precioUnitario: i.precioUnitario,
                subtotal: i.subtotal,
                costoUnitario: i.producto.costo,
              ))
          .toList();

      final remitoId = await remitoService.insertar(remito, detalles);

      if (!mounted) return;
      setState(() => guardando = false);
      await _imprimirOCompartirRemito(remito, detalles, remitoId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el remito: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final descuentoCliente = clienteSeleccionado?.descuento ?? 0;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Nuevo Remito'),
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
                        DropdownButtonFormField<Cliente>(
                          initialValue: clienteSeleccionado,
                          decoration: InputDecoration(
                            labelText: 'Cliente',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: clientes
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.nombre),
                                ),
                              )
                              .toList(),
                          onChanged: _seleccionarCliente,
                          hint: const Text('Seleccionar cliente'),
                        ),
                        if (descuentoCliente > 0) ...[
                          const SizedBox(height: 8),
                          Chip(
                            avatar: const Icon(Icons.percent, size: 18),
                            label: Text(
                              'Descuento del cliente: ${descuentoCliente.toStringAsFixed(1)}%',
                            ),
                          ),
                        ],
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
                                  'x${item.cantidad} × \$${item.precioUnitario.toStringAsFixed(2)}'
                                  ' · Stock: ${item.producto.stock}',
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
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() => items.removeAt(idx));
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: agregarProducto,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar producto'),
                          ),
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
                    color: Theme.of(context).cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Descuento:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${descuento.toStringAsFixed(1)}%'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: editarDescuento,
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Editar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'TOTAL',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                Text(
                                  '\$${totalConDescuento.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: guardando ? null : guardar,
                            icon: guardando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('GUARDAR'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
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
