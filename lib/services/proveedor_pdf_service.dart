import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/producto.dart';

/// Extrae texto de PDFs simples (FlateDecode + Tj/TJ) y parsea
/// presupuestos/remitos tipo Cuero Sur:
/// `TOTAL COD PRECIO_UNIT CANT UNI DESCRIPCION`
class ProveedorPdfService {
  Future<({List<Producto> productos, int filasTotales, int omitidas, String texto})>
      leerArchivo(String path) async {
    final bytes = await File(path).readAsBytes();
    return leerBytes(Uint8List.fromList(bytes));
  }

  ({List<Producto> productos, int filasTotales, int omitidas, String texto})
      leerBytes(Uint8List bytes) {
    final texto = extraerTexto(bytes);
    final parseado = parsearLineasPresupuesto(texto);
    return (
      productos: parseado.productos,
      filasTotales: parseado.filasTotales,
      omitidas: parseado.omitidas,
      texto: texto,
    );
  }

  /// Extrae texto legible de un PDF con streams FlateDecode.
  String extraerTexto(Uint8List bytes) {
    final buffer = StringBuffer();
    var i = 0;
    final streamMark = ascii.encode('stream');
    final endMark = ascii.encode('endstream');

    while (i < bytes.length) {
      final start = _indexOf(bytes, streamMark, i);
      if (start < 0) break;
      var dataStart = start + streamMark.length;
      if (dataStart < bytes.length && bytes[dataStart] == 0x0d) dataStart++;
      if (dataStart < bytes.length && bytes[dataStart] == 0x0a) dataStart++;

      final end = _indexOf(bytes, endMark, dataStart);
      if (end < 0) break;
      var dataEnd = end;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0a) dataEnd--;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0d) dataEnd--;

      final compressed = Uint8List.sublistView(bytes, dataStart, dataEnd);
      Uint8List? inflated;
      try {
        inflated = Uint8List.fromList(ZLibCodec().decode(compressed));
      } catch (_) {
        try {
          inflated = Uint8List.fromList(
            ZLibCodec(raw: true).decode(compressed),
          );
        } catch (_) {
          i = end + endMark.length;
          continue;
        }
      }
      buffer.writeln(
        _textoDesdeContentStream(utf8.decode(inflated, allowMalformed: true)),
      );
      i = end + endMark.length;
    }

    if (buffer.isEmpty) {
      buffer.write(_textoDesdeLiterales(String.fromCharCodes(bytes)));
    }
    return buffer.toString();
  }

  int _indexOf(Uint8List haystack, List<int> needle, int from) {
    if (needle.isEmpty || from >= haystack.length) return -1;
    outer:
    for (var i = from; i <= haystack.length - needle.length; i++) {
      for (var k = 0; k < needle.length; k++) {
        if (haystack[i + k] != needle[k]) continue outer;
      }
      return i;
    }
    return -1;
  }

  String _textoDesdeContentStream(String content) {
    final out = StringBuffer();
    final tjArray = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    for (final m in tjArray.allMatches(content)) {
      final inner = m.group(1)!;
      final parts = RegExp(r'\((?:\\.|[^\\)])*\)').allMatches(inner);
      final line = StringBuffer();
      for (final p in parts) {
        final lit = p.group(0)!;
        line.write(_unescapePdfString(lit.substring(1, lit.length - 1)));
      }
      final s = line.toString().trimRight();
      if (s.isNotEmpty) out.writeln(s);
    }
    final tjSimple = RegExp(r'\((?:\\.|[^\\)])*\)\s*Tj');
    for (final m in tjSimple.allMatches(content)) {
      final lit = m.group(0)!;
      final open = lit.indexOf('(');
      final close = lit.lastIndexOf(')');
      if (open >= 0 && close > open) {
        final s = _unescapePdfString(lit.substring(open + 1, close)).trimRight();
        if (s.isNotEmpty) out.writeln(s);
      }
    }
    return out.toString();
  }

  String _textoDesdeLiterales(String raw) {
    final out = StringBuffer();
    for (final m in RegExp(r'\((?:\\.|[^\\)]){2,}\)').allMatches(raw)) {
      final s = m.group(0)!;
      out.writeln(_unescapePdfString(s.substring(1, s.length - 1)));
    }
    return out.toString();
  }

  String _unescapePdfString(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\');
  }

  static final _reMoney = RegExp(r'^[\d.]+,\d{2}$');
  static final _reLineaUnica = RegExp(
    r'^\s*([\d.]+,\d{2})\s+(\S+)\s+([\d.]+,\d{2})\s+(\d+)\s+(\S+)\s+(.+?)\s*$',
  );
  static final _reCantUnidadDesc = RegExp(
    r'^(\d+)\s*(C/U|PAR|LAT|BOT|HJA|KG|UNI|DOC|PZA)(.*)$',
    caseSensitive: false,
  );

  /// Parsea líneas de presupuesto/remito Cuero Sur (y similares).
  /// Soporta:
  /// - una línea completa (texto ya unido)
  /// - campos en líneas separadas (extracción Tj/TJ típica)
  ({List<Producto> productos, int filasTotales, int omitidas})
      parsearLineasPresupuesto(String texto) {
    final productos = <Producto>[];
    var filasTotales = 0;
    var omitidas = 0;

    final lines = texto
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 1) Intento líneas completas.
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('COD') && upper.contains('ARTICULO')) continue;
      if (upper.startsWith('TOTAL ') && !_reLineaUnica.hasMatch(line)) continue;
      if (upper.startsWith('KG.') || upper.startsWith('HOJA ')) continue;

      final m = _reLineaUnica.firstMatch(line);
      if (m == null) continue;
      filasTotales++;
      final p = _productoDesdeCampos(
        codigo: m.group(2)!,
        precioUnitRaw: m.group(3)!,
        descRaw: m.group(6)!,
      );
      if (p == null) {
        omitidas++;
      } else {
        productos.add(p);
      }
    }
    if (productos.isNotEmpty) {
      return (
        productos: productos,
        filasTotales: filasTotales,
        omitidas: omitidas,
      );
    }

    // 2) Campos en líneas sueltas (extracción Tj/TJ):
    //    TOTAL
    //    COD
    //    PRECIO_UNIT
    //    {cant}{UNI}{descripcion}   ej: 2C/UPICTO CUERO... / 1PARpar PLANTISUR...
    for (var i = 0; i + 3 < lines.length; i++) {
      if (!_reMoney.hasMatch(lines[i])) continue;
      final codigo = lines[i + 1];
      if (_reMoney.hasMatch(codigo)) continue;
      // Evitar tomar encabezados/fechas como código.
      if (codigo.contains(':') || codigo.length > 24) continue;
      if (!_reMoney.hasMatch(lines[i + 2])) continue;
      final cola = lines[i + 3];
      final matchCola = _reCantUnidadDesc.firstMatch(cola);
      if (matchCola == null) continue;

      var desc = (matchCola.group(3) ?? '').trim();
      desc = desc.replaceFirst(
        RegExp(r'^(par|c/u|lat|bot|hja)\s*', caseSensitive: false),
        '',
      );

      filasTotales++;
      final p = _productoDesdeCampos(
        codigo: codigo,
        precioUnitRaw: lines[i + 2],
        descRaw: desc,
      );
      if (p == null) {
        omitidas++;
      } else {
        productos.add(p);
        i += 3; // avanzar al siguiente bloque
      }
    }

    return (
      productos: productos,
      filasTotales: filasTotales,
      omitidas: omitidas,
    );
  }

  Producto? _productoDesdeCampos({
    required String codigo,
    required String precioUnitRaw,
    required String descRaw,
  }) {
    final cod = codigo.trim();
    final precioUnit = _parseImporte(precioUnitRaw);
    var desc = descRaw.trim();
    desc = desc.replaceFirst(
      RegExp(r'^(par|c/u|lat|bot|hja)\s+', caseSensitive: false),
      '',
    );
    if (cod.isEmpty || desc.isEmpty || precioUnit <= 0) return null;
    if (RegExp(r'^\d{4,}$').hasMatch(cod) && desc.length < 4) return null;
    // Pie de página / totales sueltos.
    if (cod.toUpperCase() == 'TOTAL') return null;

    return Producto(
      codigo: cod,
      descripcion: desc,
      marca: '',
      categoria: '',
      proveedor: '',
      ubicacion: '',
      stock: 0,
      costo: precioUnit,
      precio: 0,
      observaciones: '',
      foto: '',
    );
  }

  double _parseImporte(String raw) {
    var v = raw.trim().replaceAll('\$', '').replaceAll(' ', '');
    if (v.contains(',') && v.contains('.')) {
      v = v.replaceAll('.', '').replaceAll(',', '.');
    } else if (v.contains(',')) {
      v = v.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(v) ?? 0;
  }
}
