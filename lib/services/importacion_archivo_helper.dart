import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// Utilidades compartidas para leer Excel/CSV de importación.
class ImportacionArchivoHelper {
  ImportacionArchivoHelper._();

  static String normalizarHeader(String raw) {
    return raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Future<({List<String> headers, List<List<dynamic>> filas})>
      leerArchivo(String path) async {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'csv') {
      return _leerCsv(path);
    }
    return _leerExcel(path);
  }

  static Future<({List<String> headers, List<List<dynamic>> filas})>
      _leerCsv(String path) async {
    final contenido = await File(path).readAsString();
    final delimitador = contenido.contains(';') ? ';' : ',';
    final filas = CsvDecoder(fieldDelimiter: delimitador).convert(contenido);
    if (filas.isEmpty) {
      return (headers: <String>[], filas: <List<dynamic>>[]);
    }
    return (
      headers: filas.first.map((e) => e.toString()).toList(),
      filas: filas.skip(1).toList(),
    );
  }

  static Future<({List<String> headers, List<List<dynamic>> filas})>
      _leerExcel(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    // Preferir hoja de datos (no Instrucciones)
    Sheet? sheet;
    for (final name in excel.tables.keys) {
      if (name.toLowerCase() != 'instrucciones') {
        sheet = excel.tables[name];
        break;
      }
    }
    sheet ??= excel.tables[excel.getDefaultSheet()];
    if (sheet == null || sheet.rows.isEmpty) {
      return (headers: <String>[], filas: <List<dynamic>>[]);
    }

    final headers =
        sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
    final filas = sheet.rows
        .skip(1)
        .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
        .cast<List<dynamic>>()
        .toList();
    return (headers: headers, filas: filas);
  }

  /// Mapea encabezados a claves usando alias exactos normalizados.
  /// [ordenPrioridad] define el orden de búsqueda (más específico primero).
  static Map<T, int> mapearColumnas<T>({
    required List<String> headers,
    required Map<T, Set<String>> aliases,
    required List<T> ordenPrioridad,
  }) {
    final mapeo = <T, int>{};
    final usados = <int>{};

    for (final col in ordenPrioridad) {
      final keys = aliases[col] ?? const <String>{};
      for (var i = 0; i < headers.length; i++) {
        if (usados.contains(i)) continue;
        final h = normalizarHeader(headers[i]);
        if (h.isEmpty) continue;
        if (keys.contains(h)) {
          mapeo[col] = i;
          usados.add(i);
          break;
        }
      }
    }
    return mapeo;
  }

  static double parsearNumero(String valor) {
    valor = valor.replaceAll(RegExp(r'[^\d,\.]'), '');
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
      valor = valor.replaceAll(',', '.');
    }
    return double.tryParse(valor) ?? 0;
  }
}
