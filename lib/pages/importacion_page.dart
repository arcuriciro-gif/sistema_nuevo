import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../services/importacion_archivo_helper.dart';
import '../services/lista_precio_service.dart';
import '../services/plantilla_importacion_service.dart';
import '../services/precio_calculador_service.dart';
import '../services/producto_service.dart';
import '../theme/module_app_bar.dart';

enum _Col {
  codigo,
  descripcion,
  marca,
  categoria,
  proveedor,
  costo,
  precio,
  precio2,
  precio3,
  stock,
  codigoBarras,
}

const _colAliases = <_Col, Set<String>>{
  _Col.codigo: {'codigo', 'cod', 'sku', 'articulo', 'art', 'code'},
  _Col.descripcion: {
    'descripcion',
    'desc',
    'producto',
    'nombre',
    'detalle',
    'name',
  },
  _Col.marca: {'marca', 'brand', 'fabricante'},
  _Col.categoria: {'categoria', 'cat', 'rubro', 'tipo'},
  _Col.proveedor: {'proveedor', 'prov', 'supplier', 'vendor'},
  _Col.costo: {'costo', 'cost', 'precioneto', 'neto', 'preciocosto', 'pcosto'},
  _Col.precio: {
    'precio1',
    'precio',
    'pvp',
    'precioventa',
    'pventa',
    'price',
    'lista1',
  },
  _Col.precio2: {'precio2', 'pvp2', 'lista2'},
  _Col.precio3: {'precio3', 'pvp3', 'lista3'},
  _Col.stock: {'stock', 'cant', 'cantidad', 'qty'},
  _Col.codigoBarras: {
    'codigobarras',
    'barcode',
    'ean',
    'barras',
    'codigodebarras',
  },
};

/// Orden: más específico primero (precio3/2 antes que precio1).
const _ordenMapeo = [
  _Col.codigoBarras,
  _Col.precio3,
  _Col.precio2,
  _Col.precio,
  _Col.costo,
  _Col.codigo,
  _Col.descripcion,
  _Col.marca,
  _Col.categoria,
  _Col.proveedor,
  _Col.stock,
];

class ImportacionPage extends StatefulWidget {
  const ImportacionPage({super.key});

  @override
  State<ImportacionPage> createState() => _ImportacionPageState();
}

enum _Estado { inicio, vista_previa, importando, listo }

class _ImportacionPageState extends State<ImportacionPage> {
  final ProductoService _svc = ProductoService();
  final _plantillas = PlantillaImportacionService.instance;

  _Estado _estado = _Estado.inicio;

  List<String> _headers = [];
  List<List<dynamic>> _filas = [];
  Map<_Col, int> _mapeo = {};

  int _importados = 0;
  int _actualizados = 0;
  int _saltados = 0;
  String _mensajeError = '';
  bool _descargando = false;

  Future<void> _descargarPlantilla() async {
    setState(() => _descargando = true);
    try {
      final file = await _plantillas.generarPlantillaProductos();
      await _plantillas.compartirArchivo(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plantilla guardada en:\n${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la plantilla: $e')),
      );
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    try {
      final data = await ImportacionArchivoHelper.leerArchivo(path);
      if (data.headers.isEmpty) {
        setState(() => _mensajeError = 'El archivo está vacío.');
        return;
      }
      final mapeo = ImportacionArchivoHelper.mapearColumnas<_Col>(
        headers: data.headers,
        aliases: _colAliases,
        ordenPrioridad: _ordenMapeo,
      );
      if (!mounted) return;
      setState(() {
        _headers = data.headers;
        _filas = data.filas;
        _mapeo = mapeo;
        _estado = _Estado.vista_previa;
        _mensajeError = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensajeError = 'Error al leer el archivo: $e');
    }
  }

  Future<void> _importar() async {
    if (_mapeo[_Col.codigo] == null) {
      setState(() => _mensajeError = 'Debe asignar al menos la columna Código.');
      return;
    }

    setState(() {
      _estado = _Estado.importando;
      _importados = 0;
      _actualizados = 0;
      _saltados = 0;
      _mensajeError = '';
    });

    final codigoIdx = _mapeo[_Col.codigo]!;
    final listas = await ListaPrecioService().obtenerActivas();

    String valorCol(List<dynamic> fila, int? idx) =>
        (idx != null && idx < fila.length) ? fila[idx].toString().trim() : '';
    bool celdaVacia(List<dynamic> fila, int? idx) =>
        idx == null || idx >= fila.length || fila[idx].toString().trim().isEmpty;
    double numCol(List<dynamic> fila, int? idx) =>
        ImportacionArchivoHelper.parsearNumero(valorCol(fila, idx));

    for (final fila in _filas) {
      if (codigoIdx >= fila.length) {
        _saltados++;
        continue;
      }
      final codigo = fila[codigoIdx].toString().trim();
      if (codigo.isEmpty) {
        _saltados++;
        continue;
      }

      final descripcion = valorCol(fila, _mapeo[_Col.descripcion]);
      final marca = valorCol(fila, _mapeo[_Col.marca]);
      final categoria = valorCol(fila, _mapeo[_Col.categoria]);
      final proveedor = valorCol(fila, _mapeo[_Col.proveedor]);
      final codigoBarras = valorCol(fila, _mapeo[_Col.codigoBarras]);
      final stock = numCol(fila, _mapeo[_Col.stock]).toInt();

      final costoImportado =
          celdaVacia(fila, _mapeo[_Col.costo]) ? null : numCol(fila, _mapeo[_Col.costo]);
      final precio1Importado =
          celdaVacia(fila, _mapeo[_Col.precio]) ? null : numCol(fila, _mapeo[_Col.precio]);
      final precio2Importado =
          celdaVacia(fila, _mapeo[_Col.precio2]) ? null : numCol(fila, _mapeo[_Col.precio2]);
      final precio3Importado =
          celdaVacia(fila, _mapeo[_Col.precio3]) ? null : numCol(fila, _mapeo[_Col.precio3]);

      final existente = await _svc.buscarPorCodigo(codigo);

      if (existente == null) {
        var nuevo = Producto(
          codigo: codigo,
          codigoBarras: codigoBarras,
          descripcion: descripcion.isNotEmpty ? descripcion : codigo,
          marca: marca,
          categoria: categoria,
          proveedor: proveedor,
          ubicacion: '',
          stock: stock,
          costo: costoImportado ?? 0,
          precio: precio1Importado ?? 0,
          precio2: precio2Importado ?? 0,
          precio3: precio3Importado ?? 0,
          observaciones: '',
          foto: '',
        );
        nuevo = await _aplicarPreciosDesdeListas(
          nuevo,
          listas: listas,
          calcularP1: precio1Importado == null || precio1Importado <= 0,
          calcularP2: precio2Importado == null || precio2Importado <= 0,
          calcularP3: precio3Importado == null || precio3Importado <= 0,
        );
        await _svc.insertar(nuevo);
        _importados++;
      } else {
        final costoFinal = costoImportado ?? existente.costo;
        var actualizado = existente.copyWith(
          descripcion: descripcion.isNotEmpty
              ? descripcion
              : existente.descripcion,
          marca: marca.isNotEmpty ? marca : existente.marca,
          categoria: categoria.isNotEmpty ? categoria : existente.categoria,
          proveedor: proveedor.isNotEmpty ? proveedor : existente.proveedor,
          codigoBarras: codigoBarras.isNotEmpty
              ? codigoBarras
              : existente.codigoBarras,
          costo: costoFinal,
          precio: precio1Importado ?? existente.precio,
          precio2: precio2Importado ?? existente.precio2,
          precio3: precio3Importado ?? existente.precio3,
          stock: _mapeo[_Col.stock] != null ? stock : existente.stock,
        );

        // Si vino costo y faltan precios en la planilla, recalcular con % de listas.
        final recalcularPorCosto =
            costoImportado != null && costoImportado > 0;
        actualizado = await _aplicarPreciosDesdeListas(
          actualizado,
          listas: listas,
          calcularP1: recalcularPorCosto &&
              (precio1Importado == null || precio1Importado <= 0),
          calcularP2: recalcularPorCosto &&
              (precio2Importado == null || precio2Importado <= 0),
          calcularP3: recalcularPorCosto &&
              (precio3Importado == null || precio3Importado <= 0),
        );
        await _svc.actualizar(actualizado);
        _actualizados++;
      }
    }

    if (!mounted) return;
    setState(() => _estado = _Estado.listo);
  }

  /// Completa Precio1/2/3 vacíos con: costo × (1 + % lista / 100).
  Future<Producto> _aplicarPreciosDesdeListas(
    Producto producto, {
    required List<ListaPrecio> listas,
    required bool calcularP1,
    required bool calcularP2,
    required bool calcularP3,
  }) async {
    if (producto.costo <= 0) return producto;
    if (!calcularP1 && !calcularP2 && !calcularP3) return producto;
    if (listas.isEmpty) return producto;

    final calculado = await PrecioCalculadorService.instance
        .aplicarListasDesdeCosto(
      producto,
      listasActivas: listas,
      forzar: true,
    );

    return producto.copyWith(
      precio: calcularP1 ? calculado.precio : producto.precio,
      precio2: calcularP2 ? calculado.precio2 : producto.precio2,
      precio3: calcularP3 ? calculado.precio3 : producto.precio3,
      preciosListas: calculado.preciosListas,
    );
  }

  void _reiniciar() {
    setState(() {
      _estado = _Estado.inicio;
      _headers = [];
      _filas = [];
      _mapeo = {};
      _mensajeError = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Importar Productos',
        actions: [
          if (_estado == _Estado.vista_previa)
            IconButton(
              tooltip: 'Volver al inicio',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: _reiniciar,
            ),
        ],
      ),
      body: switch (_estado) {
        _Estado.inicio => _buildInicio(),
        _Estado.vista_previa => _buildVistaPrevia(),
        _Estado.importando => _buildImportando(),
        _Estado.listo => _buildListo(),
      },
    );
  }

  Widget _buildInicio() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.upload_file_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .7),
            ),
            const SizedBox(height: 24),
            Text(
              'Importación masiva de productos',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Seleccioná un archivo Excel (.xlsx) o CSV.\n'
              'Si el producto ya existe (mismo Código) se actualiza; si no, se crea.\n'
              'Si cargás Costo y dejás Precio1/2/3 vacíos, se calculan con el % '
              'de tus Listas de precios.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_mensajeError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _mensajeError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _seleccionarArchivo,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Seleccionar archivo'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _descargando ? null : _descargarPlantilla,
              icon: _descargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('Descargar plantilla Excel'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(220, 46)),
            ),
            const SizedBox(height: 20),
            _buildAyudaColumnas(),
          ],
        ),
      ),
    );
  }

  Widget _buildAyudaColumnas() {
    final orden = PlantillaImportacionService.productosHeaders;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orden de columnas de la plantilla:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...orden.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.key + 1}. ${e.value}'
                      '${e.value == 'Codigo' ? '  (obligatorio)' : ''}'
                      '${e.value.startsWith('Precio') ? '  (opcional: se calcula del costo)' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            Text(
              'Fórmula: Precio = Costo × (1 + % de la lista / 100). '
              'Configurá los % en Listas de precios. Si ponés un precio en la '
              'planilla, ese valor tiene prioridad.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVistaPrevia() {
    final previewFilas = _filas.take(5).toList();
    final colRequerida = _mapeo.containsKey(_Col.codigo);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        colRequerida
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        color: colRequerida
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Columnas detectadas (${_mapeo.length}/${_Col.values.length})',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _Col.values.map((col) {
                      final idx = _mapeo[col];
                      final ok = idx != null;
                      return Chip(
                        avatar: Icon(
                          ok ? Icons.check_rounded : Icons.close_rounded,
                          size: 14,
                          color: ok ? Colors.green : Colors.grey,
                        ),
                        label: Text(
                          ok
                              ? '${_colNombre(col)}: ${_headers[idx]}'
                              : '${_colNombre(col)}: —',
                          style: TextStyle(
                            fontSize: 11,
                            color: ok ? null : Colors.grey,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (!colRequerida)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠ No se detectó columna de Código. Usá la plantilla oficial.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Vista previa (${_filas.length} filas, primeras 5):',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columnSpacing: 16,
                columns: _headers
                    .map(
                      (h) => DataColumn(
                        label: Text(
                          h,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                    .toList(),
                rows: previewFilas.map((fila) {
                  return DataRow(
                    cells: List.generate(
                      _headers.length,
                      (i) => DataCell(
                        Text(
                          i < fila.length ? fila[i].toString() : '',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _reiniciar,
                child: const Text('Volver'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: colRequerida ? _importar : null,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text('Importar ${_filas.length} productos'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImportando() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text('Importando productos...'),
            const SizedBox(height: 8),
            Text(
              'Creados: $_importados  |  Actualizados: $_actualizados',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              '¡Importación completada!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            _resumenItem(
              Icons.add_circle_rounded,
              'Productos creados',
              _importados,
              Colors.green,
            ),
            _resumenItem(
              Icons.update_rounded,
              'Productos actualizados',
              _actualizados,
              Colors.blue,
            ),
            _resumenItem(
              Icons.skip_next_rounded,
              'Saltados (sin código)',
              _saltados,
              Colors.orange,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _reiniciar,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Importar otro archivo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenItem(IconData icon, String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          SizedBox(width: 200, child: Text(label)),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _colNombre(_Col col) {
    return switch (col) {
      _Col.codigo => 'Código',
      _Col.descripcion => 'Descripción',
      _Col.marca => 'Marca',
      _Col.categoria => 'Categoría',
      _Col.proveedor => 'Proveedor',
      _Col.costo => 'Costo',
      _Col.precio => 'Precio1',
      _Col.precio2 => 'Precio2',
      _Col.precio3 => 'Precio3',
      _Col.stock => 'Stock',
      _Col.codigoBarras => 'Código barras',
    };
  }
}
