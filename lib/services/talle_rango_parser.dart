/// Parseo de talles y rangos en descripciones de productos / listas de proveedor.
///
/// Ejemplos que entiende:
/// - `PAPI FEBO BLANCA 39 AL 42 $10000`
/// - `PAPI FEBO BLANCA 39-42 10000`
/// - `PAPI FEBO BLANCA 41 $15000`  (talle único)
/// - Producto en base: `PAPI FEBO BLANCA 41` → base + talle 41
class LineaTalleParseada {
  final String baseNombre;
  final int talleDesde;
  final int talleHasta;
  final double? costo;
  final String textoOriginal;

  const LineaTalleParseada({
    required this.baseNombre,
    required this.talleDesde,
    required this.talleHasta,
    this.costo,
    required this.textoOriginal,
  });

  bool get esRango => talleDesde != talleHasta;

  bool contieneTalle(int talle) =>
      talle >= talleDesde && talle <= talleHasta;

  String get etiquetaRango => esRango
      ? '$baseNombre $talleDesde AL $talleHasta'
      : '$baseNombre $talleDesde';
}

class ProductoTalleInfo {
  final String baseNombre;
  final int? talle;
  final String textoOriginal;

  const ProductoTalleInfo({
    required this.baseNombre,
    required this.talle,
    required this.textoOriginal,
  });
}

class TalleRangoParser {
  TalleRangoParser._();

  /// Normaliza para comparar nombres: mayúsculas, sin acentos, espacios simples.
  static String normalizarNombre(String raw) {
    var s = raw.toUpperCase().trim();
    const map = {
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static double? parsearPrecio(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return null;
    v = v.replaceAll('\$', '').replaceAll('"', '').replaceAll("'", '');
    // 10.000,50 → 10000.50 | 10,000.50 → 10000.50 | 10000
    if (v.contains(',') && v.contains('.')) {
      final lastComma = v.lastIndexOf(',');
      final lastDot = v.lastIndexOf('.');
      if (lastComma > lastDot) {
        v = v.replaceAll('.', '').replaceAll(',', '.');
      } else {
        v = v.replaceAll(',', '');
      }
    } else if (v.contains(',')) {
      // 10000,50 o 10.000 con coma rara → si hay 3 dígitos tras coma es decimal
      final parts = v.split(',');
      if (parts.length == 2 && parts[1].length <= 2) {
        v = '${parts[0].replaceAll('.', '')}.${parts[1]}';
      } else {
        v = v.replaceAll(',', '');
      }
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(v)) {
      // 10.000 o 1.000.000 (miles)
      v = v.replaceAll('.', '');
    }
    return double.tryParse(v);
  }

  /// Parsea una línea de proveedor con rango o talle único + precio opcional.
  static LineaTalleParseada? parsearLineaProveedor(String texto) {
    final original = texto.trim();
    if (original.isEmpty) return null;

    // Quitar precio al final si está: $10000 / 10000 / 10.000,50
    final precioMatch = RegExp(
      r'[\s\$]*\$?\s*([\d]{1,3}(?:[.\s]\d{3})*(?:[.,]\d{1,2})?|[\d]+(?:[.,]\d{1,2})?)\s*$',
    ).firstMatch(original);

    double? costo;
    var sinPrecio = original;
    if (precioMatch != null) {
      final posible = parsearPrecio(precioMatch.group(1)!);
      // Evitar tomar el talle como precio: si el "precio" es un entero chico
      // y no hay $ delante, puede ser el talle. Solo aceptar si hay $ o
      // el número es >= 100 o tiene decimales, O si queda un rango/talle antes.
      final tieneSigno = original.contains('\$');
      final resto = original.substring(0, precioMatch.start).trim();
      if (posible != null &&
          (tieneSigno ||
              posible >= 100 ||
              (precioMatch.group(1)!.contains(',') ||
                  precioMatch.group(1)!.contains('.')) ||
              _pareceTenerTalle(resto))) {
        costo = posible;
        sinPrecio = resto;
      }
    }

    // Rango: NOMBRE 39 AL 42 | 39 A 42 | 39-42 | 39/42
    final rango = RegExp(
      r'^(.*?)\s+(\d{1,3})\s*(?:AL|A|A\/|-|–|/)\s*(\d{1,3})\s*$',
      caseSensitive: false,
    ).firstMatch(sinPrecio);

    if (rango != null) {
      final base = rango.group(1)!.trim();
      final desde = int.parse(rango.group(2)!);
      final hasta = int.parse(rango.group(3)!);
      if (base.isEmpty) return null;
      return LineaTalleParseada(
        baseNombre: normalizarNombre(base),
        talleDesde: desde <= hasta ? desde : hasta,
        talleHasta: desde <= hasta ? hasta : desde,
        costo: costo,
        textoOriginal: original,
      );
    }

    // Talle único al final: NOMBRE 41
    final unico = RegExp(r'^(.*?)\s+(\d{1,3})\s*$').firstMatch(sinPrecio);
    if (unico != null) {
      final base = unico.group(1)!.trim();
      final talle = int.parse(unico.group(2)!);
      if (base.isEmpty) return null;
      // Evitar bases que son solo números
      if (RegExp(r'^\d+$').hasMatch(base)) return null;
      return LineaTalleParseada(
        baseNombre: normalizarNombre(base),
        talleDesde: talle,
        talleHasta: talle,
        costo: costo,
        textoOriginal: original,
      );
    }

    return null;
  }

  /// Extrae base + talle de un producto (campo talle o final de descripción).
  static ProductoTalleInfo parsearProducto({
    required String descripcion,
    String talleCampo = '',
  }) {
    final original = descripcion.trim();
    final talleExplicit = talleCampo.trim();

    if (talleExplicit.isNotEmpty) {
      final n = int.tryParse(talleExplicit);
      if (n != null) {
        // Quitar talle del final de la descripción si coincide
        var base = original;
        final cola = RegExp(r'\s+' + RegExp.escape(talleExplicit) + r'\s*$')
            .firstMatch(original);
        if (cola != null) {
          base = original.substring(0, cola.start).trim();
        }
        return ProductoTalleInfo(
          baseNombre: normalizarNombre(base.isNotEmpty ? base : original),
          talle: n,
          textoOriginal: original,
        );
      }
    }

    final m = RegExp(r'^(.*?)\s+(\d{1,3})\s*$').firstMatch(original);
    if (m != null) {
      final base = m.group(1)!.trim();
      if (base.isNotEmpty && !RegExp(r'^\d+$').hasMatch(base)) {
        return ProductoTalleInfo(
          baseNombre: normalizarNombre(base),
          talle: int.parse(m.group(2)!),
          textoOriginal: original,
        );
      }
    }

    return ProductoTalleInfo(
      baseNombre: normalizarNombre(original),
      talle: null,
      textoOriginal: original,
    );
  }

  static bool _pareceTenerTalle(String texto) {
    return RegExp(
      r'\d{1,3}\s*(?:AL|A|A\/|-|–|/)\s*\d{1,3}\s*$',
      caseSensitive: false,
    ).hasMatch(texto) ||
        RegExp(r'\s\d{1,3}\s*$').hasMatch(texto);
  }
}
