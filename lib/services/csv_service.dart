import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/producto.dart';
import 'comparador_service.dart';
import 'importacion_archivo_helper.dart';
import 'producto_service.dart';
import 'talle_rango_parser.dart';

class CsvService {
  final ProductoService produtoService = ProductoService();
  final ComparadorService comparadorService = ComparadorService();

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
      // Primera carga: solo insertar filas con código (no rangos).
      final conCodigo = productos
          .where((p) => p.codigo.trim().isNotEmpty && p.codigo != 'RANGO')
          .toList();
      if (conCodigo.isNotEmpty) {
        await produtoService.insertarLista(conCodigo);
      }
    } else {
      await comparadorService.compararProductos(
        productos,
        proveedor: proveedor,
      );
    }
    return productos.length;
  }

  /// Lee CSV o Excel de lista de proveedor.
  ///
  /// Formatos soportados:
  /// 1) Legacy 18 columnas (`;`) — codigo en col 0, desc 1, costo 17
  /// 2) Flexible con encabezados: Codigo / Descripcion|Articulo / Costo|Precio
  /// 3) Simple 2 columnas: Articulo ; Costo  (ideal para rangos de talle)
  /// 4) 1 columna: texto completo `PAPI FEBO BLANCA 39 AL 42 $10000`
  Future<List<Producto>> leerArchivo() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (resultado == null || resultado.files.single.path == null) {
      return [];
    }
    final path = resultado.files.single.path!;
    final ext = path.split('.').last.toLowerCase();

    if (ext == 'csv') {
      return _leerCsv(path);
    }
    return _leerFlexible(path);
  }

  Future<List<Producto>> _leerCsv(String path) async {
    final archivo = File(path);
    final contenido = await archivo.readAsString();
    final delimitador = contenido.contains(';') ? ';' : ',';
    final filas = CsvDecoder(fieldDelimiter: delimitador).convert(contenido);
    if (filas.isEmpty) return [];

    // ¿Legacy 18 columnas?
    final primeraData = filas.length > 1 ? filas[1] : <dynamic>[];
    if (primeraData.length >= 18) {
      return _parseLegacy18(filas);
    }

    return _parseFilasFlexibles(
      filas.first.map((e) => e.toString()).toList(),
      filas.skip(1).toList(),
    );
  }

  Future<List<Producto>> _leerFlexible(String path) async {
    final data = await ImportacionArchivoHelper.leerArchivo(path);
    if (data.headers.isEmpty) return [];
    return _parseFilasFlexibles(data.headers, data.filas);
  }

  List<Producto> _parseLegacy18(List<List<dynamic>> filas) {
    final productos = <Producto>[];
    for (int i = 1; i < filas.length; i++) {
      final fila = filas[i];
      if (fila.length < 18) continue;
      final codigo = fila[0].toString().trim();
      if (codigo.isEmpty) continue;
      productos.add(
        Producto(
          codigo: codigo,
          descripcion: fila[1].toString(),
          marca: fila[14].toString(),
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 0,
          costo: convertirNumero(fila[17].toString()),
          precio: convertirNumero(fila[4].toString()),
          observaciones: '',
          foto: '',
        ),
      );
    }
    return productos;
  }

  List<Producto> _parseFilasFlexibles(
    List<String> headers,
    List<List<dynamic>> filas,
  ) {
    final headersNorm = headers
        .map(ImportacionArchivoHelper.normalizarHeader)
        .toList();

    int? idxDe(Set<String> aliases) {
      for (var i = 0; i < headersNorm.length; i++) {
        if (aliases.contains(headersNorm[i])) return i;
      }
      return null;
    }

    // Detectar si la primera fila es encabezado o dato
    var dataRows = filas;
    var codigoIdx = idxDe({'codigo', 'cod', 'sku', 'articulo', 'art'});
    var descIdx = idxDe({
      'descripcion',
      'desc',
      'producto',
      'nombre',
      'detalle',
      'articulo',
      'item',
      'linea',
    });
    var costoIdx = idxDe({
      'costo',
      'precio',
      'preciocosto',
      'pvp',
      'importe',
      'valor',
    });

    final pareceHeader =
        codigoIdx != null ||
        descIdx != null ||
        costoIdx != null ||
        headersNorm.any(
          (h) =>
              h.contains('cod') ||
              h.contains('desc') ||
              h.contains('precio') ||
              h.contains('costo') ||
              h.contains('articulo'),
        );

    if (!pareceHeader && headers.isNotEmpty) {
      // Primera fila es dato: 1 col texto, o 2 cols articulo+precio
      dataRows = [headers.map((e) => e as dynamic).toList(), ...filas];
      if (headers.length == 1) {
        descIdx = 0;
        codigoIdx = null;
        costoIdx = null;
      } else if (headers.length >= 2) {
        descIdx = 0;
        costoIdx = 1;
        codigoIdx = null;
      }
    }

    // Si "articulo" se usó como codigo y no hay desc, usar esa col como desc
    if (descIdx == null && codigoIdx != null) {
      final h = headersNorm[codigoIdx];
      if (h == 'articulo' || h == 'nombre' || h == 'producto') {
        descIdx = codigoIdx;
        codigoIdx = null;
      }
    }

    final productos = <Producto>[];
    for (final fila in dataRows) {
      String valor(int? idx) =>
          (idx != null && idx < fila.length) ? fila[idx].toString().trim() : '';

      var codigo = valor(codigoIdx);
      var desc = valor(descIdx);
      var costo = costoIdx != null ? convertirNumero(valor(costoIdx)) : 0.0;

      // Una sola celda con todo el texto
      if (desc.isEmpty && codigo.isEmpty && fila.isNotEmpty) {
        desc = fila.map((e) => e.toString()).join(' ').trim();
      }
      if (desc.isEmpty && codigo.isNotEmpty && codigoIdx == descIdx) {
        desc = codigo;
        codigo = '';
      }

      // Si no hay costo en columna, intentar sacarlo del texto
      if (costo <= 0 && desc.isNotEmpty) {
        final parsed = TalleRangoParser.parsearLineaProveedor(desc);
        if (parsed?.costo != null) {
          costo = parsed!.costo!;
        }
      }

      if (desc.isEmpty && codigo.isEmpty) continue;
      if (costo <= 0 && codigo.isEmpty) {
        // Sin precio ni código no sirve para comparar
        final parsed = TalleRangoParser.parsearLineaProveedor(desc);
        if (parsed?.costo == null) continue;
        costo = parsed!.costo!;
      }

      productos.add(
        Producto(
          codigo: codigo,
          descripcion: desc.isNotEmpty ? desc : codigo,
          marca: '',
          categoria: '',
          proveedor: '',
          ubicacion: '',
          stock: 0,
          costo: costo,
          precio: 0,
          observaciones: '',
          foto: '',
        ),
      );
    }
    return productos;
  }

  double convertirNumero(String valor) {
    return TalleRangoParser.parsearPrecio(valor) ?? 0;
  }

  /// Exports a generic set of rows to a CSV file (used by the Reportes page).
  Future<File> exportarCsv(
    String nombreArchivo,
    List<String> headers,
    List<List<dynamic>> filas,
  ) async {
    final csv = const CsvEncoder(
      fieldDelimiter: ';',
    ).convert([headers, ...filas]);

    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'reportes'));
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final archivo = File(p.join(carpeta.path, nombreArchivo));
    // BOM UTF-8 para que Excel en Windows abra bien acentos y ñ.
    return archivo.writeAsString('\uFEFF$csv', flush: true);
  }
}
