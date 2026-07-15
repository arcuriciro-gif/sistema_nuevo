import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/sync/media_sync_service.dart';
import '../core/utils/media_path.dart';
import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../services/auth_service.dart';
import '../services/lista_precio_service.dart';
import '../services/producto_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'historial_precios_page.dart';
import 'scanner_page.dart';

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
  final codigoBarrasController = TextEditingController();
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
  bool _guardando = false;

  @override
  void initState() {
    super.initState();

    if (widget.producto != null) {
      final p = widget.producto!;
      codigoController.text = p.codigo;
      codigoBarrasController.text = p.codigoBarras;
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
      foto = p.fotoPrincipal;
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
    codigoBarrasController.dispose();
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
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;

    final picker = ImagePicker();
    final imagen = await picker.pickImage(
      source: origen,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (imagen == null) return;

    // Guardar en carpeta permanente ya al elegir (no depender del temp del picker).
    final codigo = codigoController.text.trim().isNotEmpty
        ? codigoController.text.trim()
        : 'sin_codigo';
    final permanente = await MediaSyncService.instance.persistirFotoLocal(
      sourcePath: imagen.path,
      codigoProducto: codigo,
    );
    if (!mounted) return;
    setState(() => foto = permanente ?? imagen.path);
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
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final fotosLista = foto.trim().isEmpty
          ? <String>[]
          : <String>[foto.trim()];
      final producto = Producto(
        id: widget.producto?.id,
        codigo: codigoController.text.trim(),
        codigoBarras: codigoBarrasController.text.trim(),
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
        fotos: fotosLista,
        favorito: widget.producto?.favorito ?? false,
      );

      if (widget.producto == null) {
        await service.insertar(producto);
      } else {
        await service.actualizar(producto);
      }

      if (!mounted) return;
      final errFoto = MediaSyncService.instance.lastError;
      if (errFoto != null &&
          errFoto.isNotEmpty &&
          foto.trim().isNotEmpty &&
          !esUrlRemota(foto)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Producto guardado. La foto quedó en este equipo: $errFoto',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.mensajeUsuario(e))),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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
      appBar: buildModuleAppBar(
        context,
        title: widget.producto == null ? 'Nuevo producto' : 'Editar producto',
        actions: [
          if (widget.producto?.id != null) ...[
            ComentariosInternosButton(
              entidadTipo: 'producto',
              entidadId: '${widget.producto!.id}',
              titulo: widget.producto!.descripcion,
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Historial de cambios',
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
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            15,
            15,
            15,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            children: [
            GestureDetector(
              onTap: _guardando ? null : elegirFoto,
              child: CircleAvatar(
                radius: 60,
                backgroundImage: imageProviderDesdePath(foto),
                child: foto.isEmpty
                    ? const Icon(Icons.camera_alt, size: 40)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              MediaSyncService.instance.nubeDisponible
                  ? 'La foto se sincroniza al celular y a la PC al guardar'
                  : 'Foto guardada en este equipo. Activá la nube en Configuración para verla también en el otro dispositivo',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .6),
              ),
            ),
            const SizedBox(height: 20),
            _campo('Código', codigoController),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: codigoBarrasController,
                decoration: InputDecoration(
                  labelText: 'Código de barras',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Escanear',
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final codigo = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerPage()),
                      );
                      if (codigo == null || codigo.trim().isEmpty) return;
                      setState(() => codigoBarrasController.text = codigo.trim());
                    },
                  ),
                ),
              ),
            ),
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
                onPressed: _guardando ? null : guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'GUARDANDO…' : 'GUARDAR'),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
