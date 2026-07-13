/// Normalización y empareje de descripciones de productos / listas de proveedor.
class TextoProducto {
  TextoProducto._();

  static const _acentos = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
    'à': 'a',
    'è': 'e',
    'ì': 'i',
    'ò': 'o',
    'ù': 'u',
  };

  /// Minúsculas, sin acentos, espacios colapsados, sin signos raros.
  static String normalizar(String raw) {
    var t = raw.trim().toLowerCase();
    final buf = StringBuffer();
    for (final rune in t.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(_acentos[ch] ?? ch);
    }
    t = buf.toString();
    t = t.replaceAll(RegExp(r'[^\w\s\-]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Unificar "39 al 45" / "39 a 45" → "39-45"
    t = t.replaceAllMapped(
      RegExp(r'\b(\d+)\s*(?:al|a|hasta)\s*(\d+)\b'),
      (m) => '${m[1]}-${m[2]}',
    );
    return t;
  }

  /// Extrae rango de talle al final: "papi blanco 39-42" → base + 39..42
  static ({String base, int? desde, int? hasta}) parsearRangoTalle(
    String descripcion,
  ) {
    final n = normalizar(descripcion);
    final m = RegExp(r'^(.*?)\s+(\d+)\s*-\s*(\d+)\s*$').firstMatch(n);
    if (m != null) {
      final a = int.tryParse(m[2]!);
      final b = int.tryParse(m[3]!);
      if (a != null && b != null) {
        return (
          base: m[1]!.trim(),
          desde: a <= b ? a : b,
          hasta: a <= b ? b : a,
        );
      }
    }
    return (base: n, desde: null, hasta: null);
  }

  static int? parsearTalle(String talle) {
    final m = RegExp(r'(\d+)').firstMatch(talle.trim());
    if (m == null) return null;
    return int.tryParse(m[1]!);
  }

  /// Talle numérico al final de una descripción: "papi blanco 40" → 40.
  /// No toma rangos ("39-42").
  static int? parsearTalleAlFinal(String descripcion) {
    final n = normalizar(descripcion);
    if (RegExp(r'\d+\s*-\s*\d+\s*$').hasMatch(n)) return null;
    final m = RegExp(r'^(.*?)\s+(\d+)\s*$').firstMatch(n);
    if (m == null) return null;
    return int.tryParse(m[2]!);
  }

  /// Quita el talle final numérico de una descripción normalizada.
  static String quitarTalleFinal(String descripcion) {
    final n = normalizar(descripcion);
    final m = RegExp(r'^(.*?)\s+\d+\s*$').firstMatch(n);
    if (m != null && !RegExp(r'\d+\s*-\s*\d+\s*$').hasMatch(n)) {
      return m[1]!.trim();
    }
    return n;
  }

  /// Texto local combinado para comparar con la lista del proveedor.
  static String textoLocal({
    required String descripcion,
    String color = '',
    String talle = '',
  }) {
    return normalizar([descripcion, color, talle]
        .where((e) => e.trim().isNotEmpty)
        .join(' '));
  }

  static String textoLocalSinTalle({
    required String descripcion,
    String color = '',
  }) {
    return normalizar([descripcion, color]
        .where((e) => e.trim().isNotEmpty)
        .join(' '));
  }
}
