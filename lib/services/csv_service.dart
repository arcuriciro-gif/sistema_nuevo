import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/producto.dart';
import 'comparador_service.dart';
import 'producto_service.dart';

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
      await produtoService.insertarLista(productos);
    } else {
      await comparadorService.compararProductos(
        productos,
        proveedor: proveedor,
      );
    }
    return productos.length;
  }

  Future<List<Producto>> leerArchivo() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (resultado == null || resultado.files.single.path == null) {
      return [];
    }
    final archivo = File(resultado.files.single.path!);
    final contenido = await archivo.readAsString();
    final filas = CsvDecoder(
      fieldDelimiter: ';',
    ).convert(contenido);
    final List<Producto> productos = [];
    for (int i = 1; i < filas.length; i++) {
      final fila = filas[i];
      if (fila.length < 18) {
        continue;
      }
      final codigo = fila[0].toString().trim();
      if (codigo.isEmpty) {
        continue;
      }
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

  double convertirNumero(String valor) {
    valor = valor.trim();
    valor = valor.replaceAll('\$', '');
    valor = valor.replaceAll('"', '');
    valor = valor.replaceAll('.', '');
    valor = valor.replaceAll(',', '.');
    if (valor.isEmpty) {
      return 0;
    }
    return double.tryParse(valor) ?? 0;
  }

  /// Exports a generic set of rows to a CSV file (used by the Reportes page).
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
