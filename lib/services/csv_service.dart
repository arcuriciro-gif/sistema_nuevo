import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/producto.dart';
import 'comparador_service.dart';
import 'producto_service.dart';
import 'proveedor_pdf_service.dart';

class CsvService {
  final ProductoService produtoService = ProductoService();
  final ComparadorService comparadorService = ComparadorService();

  static const _kwDescripcion = [
    'descripcion',
    'descripción',
    'detalle',
    'producto',
    'articulo',
    'artículo',
    'nombre',
    'item',
  ];
  static const _kwCosto = [
    'costo',
    'coste',
    'precio costo',
    'precio de costo',
    'p.costo',
    'pcosto',
    'neto',
    'precio lista',
    'precio_lista',
    'importe',
    'unitario',
    // Listas de proveedor tipo JK: "Lista 1", "Lista1", "Lista"
    'lista 1',
    'lista1',
    'lista 2',
    'lista2',
    'lista',
  ];
  static const _kwCodigo = ['codigo', 'código', 'cod', 'sku', 'code'];
  static const _kwMarca = ['marca', 'brand'];
  static const _kwPrecio = [
    'precio',
    'precio venta',
    'pvp',
    'publico',
    'público',
  ];

  Future<({int leidas, int validas, int informe, bool desdePdf})>
      analizarArchivoConProveedor(
    String proveedor,
  ) async {
    final leidas = await leerArchivoConMeta();
    final productos = leidas.productos;
    if (productos.isEmpty) {
      return (
        leidas: leidas.filasTotales,
        validas: 0,
        informe: 0,
        desdePdf: leidas.desdePdf,
      );
    }
    final existeBase = await produtoService.tieneProductos();
    if (!existeBase) {
      await produtoService.insertarLista(productos);
      return (
        leidas: leidas.filasTotales,
        validas: productos.length,
        informe: productos.length,
        desdePdf: leidas.desdePdf,
      );
    }
    // PDF presupuesto/remito: match preciso (código / modelo+color+talle).
    // Excel/CSV de lista: mantiene expansión por modelo (Leal/Profeta/Febo).
    await comparadorService.compararProductos(
      productos,
      proveedor: proveedor,
      matchPrecisoPorCodigo: leidas.desdePdf,
    );
    final informe = await comparadorService.obtenerComparacion();
    return (
      leidas: leidas.filasTotales,
      validas: productos.length,
      informe: informe.length,
      desdePdf: leidas.desdePdf,
    );
  }

  /// Analiza productos ya parseados (p. ej. tests o flujos internos).
  Future<({int leidas, int validas, int informe})> analizarProductosConProveedor(
    List<Producto> productos, {
    required String proveedor,
    bool matchPrecisoPorCodigo = false,
  }) async {
    if (productos.isEmpty) {
      return (leidas: 0, validas: 0, informe: 0);
    }
    final existeBase = await produtoService.tieneProductos();
    if (!existeBase) {
      await produtoService.insertarLista(productos);
      return (
        leidas: productos.length,
        validas: productos.length,
        informe: productos.length,
      );
    }
    await comparadorService.compararProductos(
      productos,
      proveedor: proveedor,
      matchPrecisoPorCodigo: matchPrecisoPorCodigo,
    );
    final informe = await comparadorService.obtenerComparacion();
    return (
      leidas: productos.length,
      validas: productos.length,
      informe: informe.length,
    );
  }

  @Deprecated('Usar analizarArchivoConProveedor')
  Future<int> analizarArchivo() async {
    final r = await analizarArchivoConProveedor('');
    return r.validas;
  }

  /// Lee CSV, Excel o PDF de presupuesto/remito.
  Future<List<Producto>> leerArchivo() async {
    final meta = await leerArchivoConMeta();
    return meta.productos;
  }

  Future<
      ({
        List<Producto> productos,
        int filasTotales,
        int omitidas,
        bool desdePdf,
      })> leerArchivoConMeta() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'pdf'],
    );
    if (resultado == null || resultado.files.single.path == null) {
      return (
        productos: <Producto>[],
        filasTotales: 0,
        omitidas: 0,
        desdePdf: false,
      );
    }
    final path = resultado.files.single.path!;
    final ext = p.extension(path).toLowerCase();
    if (ext == '.pdf') {
      final r = await ProveedorPdfService().leerArchivo(path);
      return (
        productos: r.productos,
        filasTotales: r.filasTotales,
        omitidas: r.omitidas,
        desdePdf: true,
      );
    }
    if (ext == '.xlsx' || ext == '.xls') {
      final r = await _leerExcel(path);
      return (
        productos: r.productos,
        filasTotales: r.filasTotales,
        omitidas: r.omitidas,
        desdePdf: false,
      );
    }
    final r = await _leerCsv(path);
    return (
      productos: r.productos,
      filasTotales: r.filasTotales,
      omitidas: r.omitidas,
      desdePdf: false,
    );
  }

  Future<({List<Producto> productos, int filasTotales, int omitidas})>
      _leerCsv(String path) async {
    final archivo = File(path);
    final contenido = await archivo.readAsString();
    // Detectar delimitador
    final primera = contenido.split('\n').first;
    final delim = primera.contains(';') &&
            primera.split(';').length >= primera.split(',').length
        ? ';'
        : ',';
    final filas = CsvDecoder(fieldDelimiter: delim).convert(contenido);
    if (filas.isEmpty) {
      return (productos: <Producto>[], filasTotales: 0, omitidas: 0);
    }
    return _filasAProductos(filas);
  }

  Future<({List<Producto> productos, int filasTotales, int omitidas})>
      _leerExcel(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    // Todas las hojas (antes solo la primera → se perdían marcas/listas).
    final productos = <Producto>[];
    var filasTotales = 0;
    var omitidas = 0;
    for (final name in excel.tables.keys) {
      final sheet = excel.tables[name];
      if (sheet == null || sheet.rows.isEmpty) continue;
      final filas = sheet.rows
          .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
      final r = _filasAProductos(filas);
      productos.addAll(r.productos);
      filasTotales += r.filasTotales;
      omitidas += r.omitidas;
    }
    return (
      productos: productos,
      filasTotales: filasTotales,
      omitidas: omitidas,
    );
  }

  ({List<Producto> productos, int filasTotales, int omitidas}) _filasAProductos(
    List<List<dynamic>> filas,
  ) {
    if (filas.isEmpty) {
      return (productos: <Producto>[], filasTotales: 0, omitidas: 0);
    }

    final headers = filas.first.map((e) => e.toString()).toList();
    final mapeo = _detectarColumnas(headers);

    // Legacy: CSV de 18+ columnas sin encabezados útiles
    final usarLegacy = mapeo['descripcion'] == null &&
        mapeo['costo'] == null &&
        headers.length >= 18;

    final productos = <Producto>[];
    final start = (mapeo.isNotEmpty || _pareceEncabezado(headers)) ? 1 : 0;
    var omitidas = 0;
    var filasDatos = 0;

    for (int i = start; i < filas.length; i++) {
      final fila = filas[i];
      if (fila.every((c) => c.toString().trim().isEmpty)) continue;
      filasDatos++;

      String descripcion;
      double costo;
      String codigo = '';
      String marca = '';
      double precio = 0;

      if (usarLegacy && fila.length >= 18) {
        codigo = fila[0].toString().trim();
        descripcion = fila[1].toString().trim();
        marca = fila[14].toString().trim();
        precio = convertirNumero(fila[4].toString());
        costo = convertirNumero(fila[17].toString());
      } else {
        descripcion = _cel(fila, mapeo['descripcion']).trim();
        // En listas de proveedor "precio" suele ser el costo de compra.
        final idxCosto = mapeo['costo'] ?? mapeo['precio'];
        costo = convertirNumero(_cel(fila, idxCosto));
        codigo = _cel(fila, mapeo['codigo']).trim();
        marca = _cel(fila, mapeo['marca']).trim();
        precio = mapeo['costo'] != null
            ? convertirNumero(_cel(fila, mapeo['precio']))
            : 0;

        // Si no detectó columnas pero hay 2+, asumir col0=desc col1=costo
        if (descripcion.isEmpty && fila.length >= 2 && mapeo.isEmpty) {
          descripcion = fila[0].toString().trim();
          costo = convertirNumero(fila[1].toString());
        }
        // Listas sin encabezado claro: col0=código col1=desc col2=precio
        if (descripcion.isEmpty && fila.length >= 3 && mapeo.isEmpty) {
          codigo = fila[0].toString().trim();
          descripcion = fila[1].toString().trim();
          costo = convertirNumero(fila[2].toString());
        }
      }

      if (descripcion.isEmpty) {
        omitidas++;
        continue;
      }
      // Antes se descartaba si el costo venía vacío: ahora entra igual
      // (aparece en el informe; no conviene actualizar costo 0 sin revisar).

      productos.add(
        Producto(
          codigo: codigo,
          descripcion: descripcion,
          marca: marca,
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 0,
          costo: costo,
          precio: precio,
          observaciones: '',
          foto: '',
        ),
      );
    }
    return (
      productos: productos,
      filasTotales: filasDatos,
      omitidas: omitidas,
    );
  }

  Map<String, int> _detectarColumnas(List<String> headers) {
    final mapeo = <String, int>{};
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      if (_kwDescripcion.any((k) => h.contains(k))) {
        mapeo.putIfAbsent('descripcion', () => i);
      } else if (_kwCosto.any((k) => h.contains(k))) {
        mapeo.putIfAbsent('costo', () => i);
      } else if (_kwCodigo.any((k) => h == k || h.startsWith('$k ') || h.startsWith('${k}_'))) {
        mapeo.putIfAbsent('codigo', () => i);
      } else if (_kwMarca.any((k) => h.contains(k))) {
        mapeo.putIfAbsent('marca', () => i);
      } else if (_kwPrecio.any((k) => h == k || h.contains(k))) {
        // Evitar pisar "precio costo"
        if (!_kwCosto.any((k) => h.contains(k))) {
          mapeo.putIfAbsent('precio', () => i);
        }
      }
    }
    return mapeo;
  }

  bool _pareceEncabezado(List<String> headers) {
    final joined = headers.join(' ').toLowerCase();
    return _kwDescripcion.any(joined.contains) ||
        _kwCosto.any(joined.contains) ||
        _kwCodigo.any(joined.contains);
  }

  String _cel(List<dynamic> fila, int? idx) {
    if (idx == null || idx >= fila.length) return '';
    return fila[idx].toString();
  }

  double convertirNumero(String valor) {
    valor = valor.trim();
    valor = valor.replaceAll('\$', '');
    valor = valor.replaceAll('"', '');
    valor = valor.replaceAll(RegExp(r'[^\d,\.\-]'), '');
    if (valor.isEmpty) return 0;
    if (valor.contains(',') && valor.contains('.')) {
      final lastComma = valor.lastIndexOf(',');
      final lastDot = valor.lastIndexOf('.');
      if (lastComma > lastDot) {
        valor = valor.replaceAll('.', '').replaceAll(',', '.');
      } else {
        valor = valor.replaceAll(',', '');
      }
    } else if (valor.contains(',')) {
      valor = valor.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(valor) ?? 0;
  }

  Future<File> exportarCsv(
    String nombreArchivo,
    List<String> headers,
    List<List<dynamic>> filas,
  ) async {
    final csv = const CsvEncoder(fieldDelimiter: ';').convert([
      headers,
      ...filas,
    ]);

    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'reportes'));
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final archivo = File(p.join(carpeta.path, nombreArchivo));
    return archivo.writeAsString(csv, flush: true);
  }
}
