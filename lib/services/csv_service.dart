import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/producto.dart';
import 'comparador_service.dart';
import 'producto_service.dart';

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

  Future<int> analizarArchivo() async {
    return analizarArchivoConProveedor('');
  }

  Future<int> analizarArchivoConProveedor(String proveedor) async {
    final productos = await leerArchivo();
    if (productos.isEmpty) {
      return 0;
    }
    final existeBase = await produtoService.tieneProductos();
    if (!existeBase) {
      await produtoService.insertarLista(productos);
    } else {
      await comparadorService.compararProductos(
        productos,
        proveedor: proveedor,
      );
    }
    return productos.length;
  }

  /// Lee CSV o Excel. Requiere columnas de **descripción** y **costo**
  /// (detectadas por encabezado; si no hay encabezado claro, usa posiciones
  /// legacy del CSV largo: desc=col2, costo=col18).
  Future<List<Producto>> leerArchivo() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (resultado == null || resultado.files.single.path == null) {
      return [];
    }
    final path = resultado.files.single.path!;
    final ext = p.extension(path).toLowerCase();
    if (ext == '.xlsx' || ext == '.xls') {
      return _leerExcel(path);
    }
    return _leerCsv(path);
  }

  Future<List<Producto>> _leerCsv(String path) async {
    final archivo = File(path);
    final contenido = await archivo.readAsString();
    // Detectar delimitador
    final primera = contenido.split('\n').first;
    final delim = primera.contains(';') &&
            primera.split(';').length >= primera.split(',').length
        ? ';'
        : ',';
    final filas = CsvDecoder(fieldDelimiter: delim).convert(contenido);
    if (filas.isEmpty) return [];
    return _filasAProductos(filas);
  }

  Future<List<Producto>> _leerExcel(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.getDefaultSheet()];
    if (sheet == null || sheet.rows.isEmpty) return [];
    final filas = sheet.rows
        .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
        .toList();
    return _filasAProductos(filas);
  }

  List<Producto> _filasAProductos(List<List<dynamic>> filas) {
    if (filas.isEmpty) return [];

    final headers = filas.first.map((e) => e.toString()).toList();
    final mapeo = _detectarColumnas(headers);

    // Legacy: CSV de 18+ columnas sin encabezados útiles
    final usarLegacy = mapeo['descripcion'] == null &&
        mapeo['costo'] == null &&
        headers.length >= 18;

    final productos = <Producto>[];
    final start = (mapeo.isNotEmpty || _pareceEncabezado(headers)) ? 1 : 0;

    for (int i = start; i < filas.length; i++) {
      final fila = filas[i];
      if (fila.every((c) => c.toString().trim().isEmpty)) continue;

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
      }

      if (descripcion.isEmpty) continue;
      if (costo <= 0 && !usarLegacy) {
        final rawCosto = _cel(fila, mapeo['costo'] ?? mapeo['precio']);
        if (rawCosto.trim().isEmpty) continue;
      }

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
    return productos;
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
