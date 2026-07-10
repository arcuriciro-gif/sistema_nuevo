import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Definición de columnas y generación de plantillas Excel/CSV
/// para importar productos, clientes y proveedores.
class PlantillaImportacionService {
  PlantillaImportacionService._();
  static final instance = PlantillaImportacionService._();

  static const productosHeaders = [
    'Codigo',
    'Descripcion',
    'Marca',
    'Categoria',
    'Proveedor',
    'Stock',
    'Costo',
    'Precio1',
    'Precio2',
    'Precio3',
    'CodigoBarras',
  ];

  static const productosEjemplo = [
    [
      'ART-001',
      'Producto de ejemplo',
      'Marca X',
      'General',
      'Proveedor SA',
      10,
      1000,
      1500,
      1400,
      1300,
      '7790000000001',
    ],
  ];

  static const clientesHeaders = [
    'Nombre',
    'Apellido',
    'Telefono',
    'WhatsApp',
    'Email',
    'Direccion',
    'Localidad',
    'Provincia',
    'CUIT',
    'CondicionIVA',
    'Descuento',
    'LimiteCuenta',
    'Observaciones',
  ];

  static const clientesEjemplo = [
    [
      'Juan',
      'Perez',
      '1122334455',
      '1122334455',
      'juan@mail.com',
      'Calle 123',
      'CABA',
      'Buenos Aires',
      '20-12345678-9',
      'Responsable Inscripto',
      0,
      50000,
      'Cliente ejemplo',
    ],
  ];

  static const proveedoresHeaders = [
    'Nombre',
    'Contacto',
    'Telefono',
    'WhatsApp',
    'Email',
    'Web',
    'CUIT',
    'CondicionesComerciales',
    'TiempoEntrega',
    'Observaciones',
  ];

  static const proveedoresEjemplo = [
    [
      'Proveedor Ejemplo SA',
      'Maria Lopez',
      '1144556677',
      '1144556677',
      'ventas@proveedor.com',
      'https://proveedor.com',
      '30-12345678-9',
      'Pago a 30 dias',
      '48 hs',
      'Proveedor de ejemplo',
    ],
  ];

  Future<File> generarPlantillaProductos() => _generarExcel(
        nombreHoja: 'Productos',
        nombreArchivo: 'plantilla_productos.xlsx',
        headers: productosHeaders,
        ejemplo: productosEjemplo,
        instrucciones: const [
          'ORDEN DE COLUMNAS (no cambies los nombres de la primera fila):',
          '1 Codigo (obligatorio) — si ya existe, se actualiza el producto',
          '2 Descripcion / Producto',
          '3 Marca',
          '4 Categoria',
          '5 Proveedor',
          '6 Stock',
          '7 Costo',
          '8 Precio1 (lista / precio de venta principal)',
          '9 Precio2',
          '10 Precio3',
          '11 CodigoBarras',
          '',
          'Tips: borra la fila de ejemplo antes de importar.',
          'Acepta .xlsx o .CSV (separador ; o ,).',
          'Numeros: podes usar 1500,50 o 1500.50',
        ],
      );

  Future<File> generarPlantillaClientes() => _generarExcel(
        nombreHoja: 'Clientes',
        nombreArchivo: 'plantilla_clientes.xlsx',
        headers: clientesHeaders,
        ejemplo: clientesEjemplo,
        instrucciones: const [
          'ORDEN DE COLUMNAS (no cambies los nombres de la primera fila):',
          '1 Nombre (obligatorio)',
          '2 Apellido',
          '3 Telefono',
          '4 WhatsApp',
          '5 Email',
          '6 Direccion',
          '7 Localidad',
          '8 Provincia',
          '9 CUIT (si coincide con uno existente, se actualiza)',
          '10 CondicionIVA',
          '11 Descuento (porcentaje)',
          '12 LimiteCuenta',
          '13 Observaciones',
          '',
          'Tips: borra la fila de ejemplo antes de importar.',
        ],
      );

  Future<File> generarPlantillaProveedores() => _generarExcel(
        nombreHoja: 'Proveedores',
        nombreArchivo: 'plantilla_proveedores.xlsx',
        headers: proveedoresHeaders,
        ejemplo: proveedoresEjemplo,
        instrucciones: const [
          'ORDEN DE COLUMNAS (no cambies los nombres de la primera fila):',
          '1 Nombre (obligatorio) — si ya existe, se actualiza',
          '2 Contacto',
          '3 Telefono',
          '4 WhatsApp',
          '5 Email',
          '6 Web',
          '7 CUIT',
          '8 CondicionesComerciales',
          '9 TiempoEntrega',
          '10 Observaciones',
          '',
          'Tips: borra la fila de ejemplo antes de importar.',
        ],
      );

  Future<void> compartirArchivo(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Plantilla de importación Tata.Manager',
      ),
    );
  }

  Future<File> _generarExcel({
    required String nombreHoja,
    required String nombreArchivo,
    required List<String> headers,
    required List<List<dynamic>> ejemplo,
    required List<String> instrucciones,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheet = excel[nombreHoja];
    if (defaultSheet != null && defaultSheet != nombreHoja) {
      try {
        excel.delete(defaultSheet);
      } catch (_) {}
    }

    for (var col = 0; col < headers.length; col++) {
      _setCell(sheet, 0, col, headers[col]);
    }
    for (var row = 0; row < ejemplo.length; row++) {
      final valores = ejemplo[row];
      for (var col = 0; col < valores.length; col++) {
        _setCell(sheet, row + 1, col, valores[col]);
      }
    }

    final help = excel['Instrucciones'];
    for (var i = 0; i < instrucciones.length; i++) {
      _setCell(help, i, 0, instrucciones[i]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('No se pudo generar la plantilla Excel');
    }

    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'plantillas'));
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final archivo = File(p.join(carpeta.path, nombreArchivo));
    return archivo.writeAsBytes(bytes, flush: true);
  }

  void _setCell(Sheet sheet, int row, int col, dynamic value) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value is int) {
      cell.value = IntCellValue(value);
    } else if (value is num) {
      cell.value = DoubleCellValue(value.toDouble());
    } else {
      cell.value = TextCellValue(value?.toString() ?? '');
    }
  }
}
