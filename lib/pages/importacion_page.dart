import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/sync/import/import_batch_runner.dart';
import '../services/producto_service.dart';
import '../theme/module_app_bar.dart';

// ---------------------------------------------------------------------------
// Columnas reconocidas automáticamente
// ---------------------------------------------------------------------------
enum _Col { codigo, descripcion, marca, categoria, proveedor, costo, precio, stock }

const _colKeywords = {
  _Col.codigo: ['cod', 'codigo', 'code', 'sku', 'art', 'articulo'],
  _Col.descripcion: ['desc', 'descripcion', 'nombre', 'producto', 'detalle', 'name'],
  _Col.marca: ['marca', 'brand', 'fabricante'],
  _Col.categoria: ['cat', 'categoria', 'rubro', 'tipo'],
  _Col.proveedor: ['prov', 'proveedor', 'supplier', 'vendor'],
  _Col.costo: ['costo', 'cost', 'precio neto', 'neto', 'precio costo', 'p.costo'],
  _Col.precio: ['precio', 'pvp', 'precio venta', 'p.venta', 'price'],
  _Col.stock: ['stock', 'cant', 'cantidad', 'qty'],
};

class ImportacionPage extends StatefulWidget {
  const ImportacionPage({super.key});

  @override
  State<ImportacionPage> createState() => _ImportacionPageState();
}

enum _Estado { inicio, vista_previa, importando, listo }

class _ImportacionPageState extends State<ImportacionPage> {
  final ProductoService _svc = ProductoService();
  ImportBatchRunner? _runner;

  _Estado _estado = _Estado.inicio;

  List<String> _headers = [];
  List<List<dynamic>> _filas = [];
  Map<_Col, int> _mapeo = {};

  int _importados = 0;
  int _actualizados = 0;
  int _saltados = 0;
  int _progresoFila = 0;
  int _totalFilas = 0;
  String _mensajeError = '';
  String? _sourceName;

  // ---------------------------------------------------------------------------
  // Paso 1 – Seleccionar archivo
  // ---------------------------------------------------------------------------
  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final ext = path.split('.').last.toLowerCase();
    _sourceName = path.split(Platform.pathSeparator).last;

    try {
      if (ext == 'csv') {
        await _parsearCsv(path);
      } else {
        await _parsearExcel(path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensajeError = 'Error al leer el archivo: $e');
    }
  }

  Future<void> _parsearCsv(String path) async {
    final contenido = await File(path).readAsString();
    // Intentar detectar el delimitador
    final delimitador = contenido.contains(';') ? ';' : ',';
    final filas = CsvDecoder(fieldDelimiter: delimitador).convert(contenido);
    if (filas.isEmpty) return;
    _procesarFilas(
      filas.first.map((e) => e.toString()).toList(),
      filas.skip(1).toList(),
    );
  }

  Future<void> _parsearExcel(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.getDefaultSheet()];
    if (sheet == null || sheet.rows.isEmpty) return;

    final headers =
        sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
    final filas = sheet.rows
        .skip(1)
        .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
        .cast<List<dynamic>>()
        .toList();

    _procesarFilas(headers, filas);
  }

  void _procesarFilas(List<String> headers, List<List<dynamic>> filas) {
    final mapeo = <_Col, int>{};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      for (final entry in _colKeywords.entries) {
        if (entry.value.any((kw) => h.contains(kw))) {
          mapeo.putIfAbsent(entry.key, () => i);
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _headers = headers;
      _filas = filas;
      _mapeo = mapeo;
      _estado = _Estado.vista_previa;
      _mensajeError = '';
    });
  }

  // ---------------------------------------------------------------------------
  // Paso 2 – Vista previa y confirmación
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Paso 3 – Importar (lotes + checkpoint + sync background)
  // ---------------------------------------------------------------------------
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
      _progresoFila = 0;
      _totalFilas = _filas.length;
      _mensajeError = '';
    });

    final codigoIdx = _mapeo[_Col.codigo]!;
    final source = _sourceName ?? 'import_${_filas.length}';
    final mapping = <String, int?>{
      for (final e in _mapeo.entries) e.key.name: e.value,
    };

    String valorCol(List<dynamic> fila, int? idx) =>
        (idx != null && idx < fila.length) ? fila[idx].toString().trim() : '';
    double numCol(List<dynamic> fila, int? idx) =>
        _parsearNumero(valorCol(fila, idx));

    final runner = ImportBatchRunner(productoService: _svc);
    _runner = runner;
    try {
      final job = await runner.ensureJob(
        sourceName: source,
        totalRows: _filas.length,
        mapping: mapping,
      );
      if (mounted) {
        setState(() {
          _progresoFila = job.nextRowIndex;
          _importados = job.imported;
          _actualizados = job.updated;
          _saltados = job.skipped;
        });
      }

      final result = await runner.run(
        job: job,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progresoFila = p.nextRowIndex;
            _importados = p.imported;
            _actualizados = p.updated;
            _saltados = p.skipped;
          });
        },
        rowBuilder: (i) {
          if (i < 0 || i >= _filas.length) return null;
          final fila = _filas[i];
          if (codigoIdx >= fila.length) return null;
          final codigo = fila[codigoIdx].toString().trim();
          if (codigo.isEmpty) return null;
          return ImportRowSpec(
            codigo: codigo,
            descripcion: _mapeo[_Col.descripcion] != null
                ? valorCol(fila, _mapeo[_Col.descripcion])
                : null,
            marca: _mapeo[_Col.marca] != null
                ? valorCol(fila, _mapeo[_Col.marca])
                : null,
            categoria: _mapeo[_Col.categoria] != null
                ? valorCol(fila, _mapeo[_Col.categoria])
                : null,
            proveedor: _mapeo[_Col.proveedor] != null
                ? valorCol(fila, _mapeo[_Col.proveedor])
                : null,
            costo: _mapeo[_Col.costo] != null
                ? numCol(fila, _mapeo[_Col.costo])
                : null,
            precio: _mapeo[_Col.precio] != null
                ? numCol(fila, _mapeo[_Col.precio])
                : null,
            stock: _mapeo[_Col.stock] != null
                ? numCol(fila, _mapeo[_Col.stock]).toInt()
                : null,
          );
        },
      );

      if (!mounted) return;
      setState(() {
        _importados = result.job.imported;
        _actualizados = result.job.updated;
        _saltados = result.job.skipped;
        _progresoFila = result.job.nextRowIndex;
        _estado = result.cancelled ? _Estado.vista_previa : _Estado.listo;
        if (result.cancelled) {
          _mensajeError =
              'Importación cancelada. Al reabrir el mismo archivo continúa desde la fila ${_progresoFila + 1}.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensajeError =
            'Importación interrumpida (checkpoint guardado): $e. Al volver reanudá el mismo archivo.';
        _estado = _Estado.vista_previa;
      });
    } finally {
      _runner = null;
    }
  }

  void _cancelarImportacion() {
    _runner?.requestCancel();
  }

  double _parsearNumero(String valor) {
    valor = valor.replaceAll(RegExp(r'[^\d,\.]'), '');
    if (valor.isEmpty) return 0;
    // Si tiene punto y coma: 1.000,50 → punto es miles, coma es decimal
    if (valor.contains(',') && valor.contains('.')) {
      final lastComma = valor.lastIndexOf(',');
      final lastDot = valor.lastIndexOf('.');
      if (lastComma > lastDot) {
        valor = valor.replaceAll('.', '').replaceAll(',', '.');
      } else {
        valor = valor.replaceAll(',', '');
      }
    } else if (valor.contains(',')) {
      // Coma como decimal: 1500,50
      valor = valor.replaceAll(',', '.');
    }
    return double.tryParse(valor) ?? 0;
  }

  void _reiniciar() {
    setState(() {
      _estado = _Estado.inicio;
      _headers = [];
      _filas = [];
      _mapeo = {};
      _mensajeError = '';
      _progresoFila = 0;
      _totalFilas = 0;
      _sourceName = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
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

  // ---------------------
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
              'Seleccioná un archivo Excel (.xlsx) o CSV para importar.\n'
              'Si el producto ya existe se actualiza, si no existe se crea.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_mensajeError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _mensajeError,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _seleccionarArchivo,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Seleccionar archivo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 50),
              ),
            ),
            const SizedBox(height: 16),
            _buildAyudaColumnas(),
          ],
        ),
      ),
    );
  }

  Widget _buildAyudaColumnas() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Columnas reconocidas automáticamente:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _colKeywords.entries
                  .map(
                    (e) => Chip(
                      label: Text(
                        '${_colNombre(e.key)}: "${e.value.first}"',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------
  Widget _buildVistaPrevia() {
    final previewFilas = _filas.take(5).toList();
    final colRequerida = _mapeo.containsKey(_Col.codigo);

    return Column(
      children: [
        // Mapeo de columnas detectado
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
                        'Columnas detectadas (${_mapeo.length}/${_colKeywords.length})',
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
                          ok
                              ? Icons.check_rounded
                              : Icons.close_rounded,
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
                        '⚠ No se detectó columna de Código. Verificá los encabezados.',
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

        // Tabla de vista previa
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Vista previa (${_filas.length} filas totales, mostrando primeras 5):',
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
                    .asMap()
                    .entries
                    .map(
                      (e) => DataColumn(
                        label: Text(
                          e.value,
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

        // Botones
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

  // ---------------------
  Widget _buildImportando() {
    final total = _totalFilas <= 0 ? 1 : _totalFilas;
    final progress = (_progresoFila / total).clamp(0.0, 1.0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 24),
            Text(
              'Importando… $_progresoFila / $_totalFilas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Creados: $_importados  |  Actualizados: $_actualizados'
              '  |  Saltados: $_saltados',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Checkpoint guardado: si se cierra la app, continúa desde aquí.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _cancelarImportacion,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar (seguro)'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------
  Widget _buildListo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              '¡Importación completada!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            _resumenItem(
                Icons.add_circle_rounded, 'Productos creados', _importados,
                Colors.green),
            _resumenItem(Icons.update_rounded, 'Productos actualizados',
                _actualizados, Colors.blue),
            _resumenItem(
                Icons.skip_next_rounded, 'Saltados (sin código)', _saltados,
                Colors.orange),
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
          SizedBox(
            width: 200,
            child: Text(label),
          ),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _colNombre(_Col col) {
    switch (col) {
      case _Col.codigo:
        return 'Código';
      case _Col.descripcion:
        return 'Descripción';
      case _Col.marca:
        return 'Marca';
      case _Col.categoria:
        return 'Categoría';
      case _Col.proveedor:
        return 'Proveedor';
      case _Col.costo:
        return 'Costo';
      case _Col.precio:
        return 'Precio';
      case _Col.stock:
        return 'Stock';
    }
  }
}
