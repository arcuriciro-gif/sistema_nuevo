/// Normalización y empareje de descripciones de productos / listas de proveedor.
class TextoProducto {
  TextoProducto._();

  /// Talles de calzado habituales (evita tomar códigos de artículo como rango).
  static const int talleMin = 20;
  static const int talleMax = 50;

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
    t = t.replaceAll(RegExp(r'[^\w\s\-/]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // "39 al 45" / "39 a 45" / "39 hasta 45" → "39-45"
    t = t.replaceAllMapped(
      RegExp(r'\b(\d+)\s*(?:al|a|hasta)\s*(\d+)\b'),
      (m) => '${m[1]}-${m[2]}',
    );
    // "39/42" como rango de talle (no códigos tipo 84/91 fuera de 20-50)
    t = t.replaceAllMapped(RegExp(r'\b(\d{2})\s*/\s*(\d{2})\b'), (m) {
      final a = int.tryParse(m[1]!);
      final b = int.tryParse(m[2]!);
      if (a != null &&
          b != null &&
          _esTalleCalzado(a) &&
          _esTalleCalzado(b)) {
        return '$a-$b';
      }
      return m[0]!;
    });
    return t;
  }

  static bool _esTalleCalzado(int n) => n >= talleMin && n <= talleMax;

  /// Extrae rango de talle en cualquier posición.
  /// Ej: "febo papifutbol 39-42 blanco" → base "febo papifutbol blanco", 39..42
  static ({String base, int? desde, int? hasta}) parsearRangoTalle(
    String descripcion,
  ) {
    final n = normalizar(descripcion);
    final matches = RegExp(r'\b(\d{2})\s*-\s*(\d{2})\b').allMatches(n);
    for (final m in matches) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) continue;
      if (!_esTalleCalzado(a) || !_esTalleCalzado(b)) continue;
      // Evitar rangos absurdos (ej. 20-50 enteros de catálogo raro > 12)
      final desde = a <= b ? a : b;
      final hasta = a <= b ? b : a;
      if (hasta - desde > 15) continue;

      final base = n.replaceFirst(m.group(0)!, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return (base: base, desde: desde, hasta: hasta);
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
    final m = RegExp(r'^(.*?)\s+(\d{2})\s*$').firstMatch(n);
    if (m == null) return null;
    final t = int.tryParse(m[2]!);
    if (t == null || !_esTalleCalzado(t)) return null;
    return t;
  }

  /// Quita el talle final numérico de una descripción normalizada.
  static String quitarTalleFinal(String descripcion) {
    final n = normalizar(descripcion);
    final m = RegExp(r'^(.*?)\s+(\d{2})\s*$').firstMatch(n);
    if (m != null && !RegExp(r'\d+\s*-\s*\d+\s*$').hasMatch(n)) {
      final t = int.tryParse(m[2]!);
      if (t != null && _esTalleCalzado(t)) {
        return m[1]!.trim();
      }
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
