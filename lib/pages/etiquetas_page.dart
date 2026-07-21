import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../core/utils/busqueda_texto.dart';
import '../services/lista_precio_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../theme/module_app_bar.dart';

class EtiquetasPage extends StatefulWidget {
  const EtiquetasPage({super.key});

  @override
  State<EtiquetasPage> createState() => _EtiquetasPageState();
}

class _EtiquetasPageState extends State<EtiquetasPage> {
  final ProductoService productoService = ProductoService();
  final ListaPrecioService listaPrecioService = ListaPrecioService();
  final PdfService pdfService = PdfService();
  final TextEditingController buscarController = TextEditingController();

  List<Producto> productos = [];
  List<Producto> filtrados = [];
  List<ListaPrecio> listasActivas = [];
  final Set<int> seleccionados = {};

  String tamano = 'medium';
  ListaPrecio? listaSeleccionada;
  bool cargando = true;
  bool generando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    productos = await productoService.obtenerTodos();
    filtrados = productos;
    listasActivas = await listaPrecioService.obtenerActivas();
    if (!mounted) return;
    setState(() => cargando = false);
  }

  void _filtrar(String texto) {
    filtrados = productos
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

  double _precioParaEtiqueta(Producto p) {
    if (listaSeleccionada != null) {
      return listaSeleccionada!.calcularPrecio(p.costo);
    }
    return p.precio;
  }

  Future<void> _generarPdf({required bool compartir}) async {
    if (seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná al menos un producto')),
      );
      return;
    }

    setState(() => generando = true);
    try {
      final items = productos
          .where((p) => seleccionados.contains(p.id))
          .map((p) => {
                'codigo': p.codigo,
                'descripcion': p.descripcion,
                'precio': _precioParaEtiqueta(p),
              })
          .toList();

      final pdf = await pdfService.generateEtiquetasPdf(
        productos: items,
        tamano: tamano,
      );

      if (pdf.isEmpty) return;

      if (compartir) {
        final archivo =
            await pdfService.guardarPdfReporte(pdf, 'etiquetas.pdf');
        await SharePlus.instance.share(
          ShareParams(files: [XFile(archivo.path)]),
        );
      } else {
        await Printing.layoutPdf(onLayout: (_) async => pdf);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron generar las etiquetas: $e')),
      );
    } finally {
      if (mounted) setState(() => generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Etiquetas'),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Etiquetas de productos',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: buscarController,
                        onChanged: _filtrar,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              initialValue: tamano,
                              decoration: const InputDecoration(
                                labelText: 'Tamaño de etiqueta',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'small', child: Text('Chica')),
                                DropdownMenuItem(
                                    value: 'medium', child: Text('Mediana')),
                                DropdownMenuItem(
                                    value: 'large', child: Text('Grande')),
                              ],
                              onChanged: (v) =>
                                  setState(() => tamano = v ?? 'medium'),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<ListaPrecio?>(
                              initialValue: listaSeleccionada,
                              decoration: const InputDecoration(
                                labelText: 'Lista de precio',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Precio de lista 1'),
                                ),
                                ...listasActivas.map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l.nombre),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => listaSeleccionada = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        '${seleccionados.length} seleccionado${seleccionados.length != 1 ? 's' : ''}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(
                          () => seleccionados
                            ..clear()
                            ..addAll(filtrados
                                .where((p) => p.id != null)
                                .map((p) => p.id!)),
                        ),
                        child: const Text('Seleccionar todos'),
                      ),
                      TextButton(
                        onPressed: () => setState(seleccionados.clear),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtrados.isEmpty
                      ? const Center(child: Text('No hay productos.'))
                      : ListView.builder(
                          itemCount: filtrados.length,
                          itemBuilder: (context, i) {
                            final p = filtrados[i];
                            final marcado =
                                p.id != null && seleccionados.contains(p.id);
                            return CheckboxListTile(
                              value: marcado,
                              title: Text(p.descripcion),
                              subtitle: Text(
                                '${p.codigo} | \$${_precioParaEtiqueta(p).toStringAsFixed(2)}',
                              ),
                              onChanged: (v) {
                                if (p.id == null) return;
                                setState(() {
                                  if (v == true) {
                                    seleccionados.add(p.id!);
                                  } else {
                                    seleccionados.remove(p.id!);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              generando ? null : () => _generarPdf(compartir: false),
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('Imprimir'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              generando ? null : () => _generarPdf(compartir: true),
                          icon: generando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.share_rounded),
                          label: const Text('Compartir'),
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
