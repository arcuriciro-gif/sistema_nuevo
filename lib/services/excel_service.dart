import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExcelService {
  Future<File> exportarLibro({
    required String nombreHoja,
    required String nombreArchivo,
    required List<String> headers,
    required List<List<dynamic>> filas,
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

    for (var row = 0; row < filas.length; row++) {
      final valores = filas[row];
      for (var col = 0; col < valores.length; col++) {
        _setCell(sheet, row + 1, col, valores[col]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo Excel');
    }

    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'reportes'));
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
    } else if (value is bool) {
      cell.value = BoolCellValue(value);
    } else if (value is DateTime) {
      cell.value = TextCellValue(value.toIso8601String());
    } else {
      cell.value = TextCellValue(value?.toString() ?? '');
    }
  }
}
