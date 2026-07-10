import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../services/lista_precio_service.dart';
import '../services/producto_service.dart';
import 'historial_precios_page.dart';

class ProductoFormPage extends StatefulWidget {
  final Producto? producto;

  const ProductoFormPage({super.key, this.producto});

  @override
  State<ProductoFormPage> createState() => _ProductoFormPageState();
}

class _ProductoFormPageState extends State<ProductoFormPage> {
  final service = ProductoService();
  final ListaPrecioService listaPrecioService = ListaPrecioService();

  List<ListaPrecio> listasActivas = [];

  final codigoController = TextEditingController();
  final descripcionController = TextEditingController();
  final marcaController = TextEditingController();
  final categoriaController = TextEditingController();
  final proveedorController = TextEditingController();
  final stockController = TextEditingController();
  final costoController = TextEditingController();
  final margen1Controller = TextEditingController(text: '0');
  final margen2Controller = TextEditingController(text: '0');
  final margen3Controller = TextEditingController(text: '0');
  final precioController = TextEditingController();
  final precio2Controller = TextEditingController();
  final precio3Controller = TextEditingController();
  final observacionesController = TextEditingController();

  String foto = '';

  @override
  void initState() {
    super.initState();

    if (widget.producto != null) {
      final p = widget.producto!;
      codigoController.text = p.codigo;
      descripcionController.text = p.descripcion;
      marcaController.text = p.marca;
      categoriaController.text = p.categoria;
      proveedorController.text = p.proveedor;
      stockController.text = p.stock.toString();
      costoController.text = p.costo.toString();
      precioController.text = p.precio.toString();
      precio2Controller.text = p.precio2.toString();
      precio3Controller.text = p.precio3.toString();
      if (p.costo > 0 && p.precio > 0) {
        margen1Controller.text = ((p.precio / p.costo - 1) * 100).toStringAsFixed(1);
      }
      if (p.costo > 0 && p.precio2 > 0) {
        margen2Controller.text = ((p.precio2 / p.costo - 1) * 100).toStringAsFixed(1);
      }
      if (p.costo > 0 && p.precio3 > 0) {
        margen3Controller.text = ((p.precio3 / p.costo - 1) * 100).toStringAsFixed(1);
      }
      observacionesController.text = p.observaciones;
      foto = p.foto;
    }

    _cargarListasPrecio();
  }

  Future<void> _cargarListasPrecio() async {
    final listas = await listaPrecioService.obtenerActivas();
    if (!mounted) return;
    setState(() => listasActivas = listas);
  }

  @override
  void dispose() {
    codigoController.dispose();
    descripcionController.dispose();
    marcaController.dispose();
    categoriaController.dispose();
    proveedorController.dispose();
    stockController.dispose();
    costoController.dispose();
    margen1Controller.dispose();
    margen2Controller.dispose();
    margen3Controller.dispose();
    precioController.dispose();
    precio2Controller.dispose();
    precio3Controller.dispose();
    observacionesController.dispose();
    super.dispose();
  }

  Future<void> elegirFoto() async {
    final picker = ImagePicker();
    final imagen = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (imagen == null) return;
    setState(() => foto = imagen.path);
  }

  double _parseDbl(String text) => double.tryParse(text.replaceAll(',', '.')) ?? 0;

  void _recalcularPrecio(int lista) {
    final costo = _parseDbl(costoController.text);
    if (costo <= 0) return;
    switch (lista) {
      case 1:
        final m = _parseDbl(margen1Controller.text);
        precioController.text = (costo * (1 + m / 100)).toStringAsFixed(2);
      case 2:
        final m = _parseDbl(margen2Controller.text);
        precio2Controller.text = (costo * (1 + m / 100)).toStringAsFixed(2);
      case 3:
        final m = _parseDbl(margen3Controller.text);
        precio3Controller.text = (costo * (1 + m / 100)).toStringAsFixed(2);
    }
  }

  void _recalcularTodos() {
    _recalcularPrecio(1);
    _recalcularPrecio(2);
    _recalcularPrecio(3);
  }

  Future<void> guardar() async {
    final producto = Producto(
      id: widget.producto?.id,
      codigo: codigoController.text.trim(),
      descripcion: descripcionController.text.trim(),
      marca: marcaController.text.trim(),
      categoria: categoriaController.text.trim(),
      proveedor: proveedorController.text.trim(),
      ubicacion: widget.producto?.ubicacion ?? '',
      stock: int.tryParse(stockController.text) ?? 0,
      costo: _parseDbl(costoController.text),
      precio: _parseDbl(precioController.text),
      precio2: _parseDbl(precio2Controller.text),
      precio3: _parseDbl(precio3Controller.text),
      observaciones: observacionesController.text.trim(),
      foto: foto,
    );

    if (widget.producto == null) {
      await service.insertar(producto);
    } else {
      await service.actualizar(producto);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _campo(
    String titulo,
    TextEditingController controller, {
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: titulo,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _campoConMargen({
    required String labelPrecio,
    required String labelMargen,
    required TextEditingController precioCtrl,
    required TextEditingController margenCtrl,
    required int lista,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: precioCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: labelPrecio,
                border: const OutlineInputBorder(),
                prefixText: '\$ ',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: margenCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _recalcularPrecio(lista),
              decoration: InputDecoration(
                labelText: labelMargen,
                border: const OutlineInputBorder(),
                suffixText: '%',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.producto == null ? 'Nuevo producto' : 'Editar producto'),
        actions: [
          if (widget.producto?.id != null)
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Ver historial de precios',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistorialPreciosPage(
                      productoId: widget.producto!.id!,
                      productoDescripcion: widget.producto!.descripcion,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            GestureDetector(
              onTap: elegirFoto,
              child: CircleAvatar(
                radius: 60,
                backgroundImage: foto.isEmpty ? null : FileImage(File(foto)),
                child: foto.isEmpty ? const Icon(Icons.camera_alt, size: 40) : null,
              ),
            ),
            const SizedBox(height: 20),
            _campo('Código', codigoController),
            _campo('Descripción', descripcionController),
            _campo('Marca', marcaController),
            _campo('Categoría', categoriaController),
            _campo('Proveedor / Comprado en', proveedorController),
            _campo('Stock', stockController, keyboardType: TextInputType.number),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: costoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _recalcularTodos(),
                decoration: const InputDecoration(
                  labelText: 'Costo',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Precios de venta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Ingresá el % de ganancia para calcular el precio automáticamente, o escribí el precio directamente.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            _campoConMargen(
              labelPrecio: 'Precio Lista 1',
              labelMargen: 'Ganancia',
              precioCtrl: precioController,
              margenCtrl: margen1Controller,
              lista: 1,
            ),
            _campoConMargen(
              labelPrecio: 'Precio Lista 2',
              labelMargen: 'Ganancia',
              precioCtrl: precio2Controller,
              margenCtrl: margen2Controller,
              lista: 2,
            ),
            _campoConMargen(
              labelPrecio: 'Precio Lista 3',
              labelMargen: 'Ganancia',
              precioCtrl: precio3Controller,
              margenCtrl: margen3Controller,
              lista: 3,
            ),
            const Divider(),
            if (listasActivas.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Listas de precios dinámicas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Calculadas automáticamente según el costo y el % configurado en Listas de Precios.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: costoController,
                builder: (context, _) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: listasActivas.map((lista) {
                    final costo = _parseDbl(costoController.text);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lista.nombre,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '\$${lista.calcularPrecio(costo).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
            ],
            const SizedBox(height: 8),
            _campo('Observaciones', observacionesController),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: guardar,
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
