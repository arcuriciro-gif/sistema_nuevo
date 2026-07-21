import 'texto_producto.dart';

/// Búsqueda flexible por tokens (AND): "papi negro 42" coincide con
/// "febo papifutbol goma negro 34" si cada token aparece como subcadena
/// en el texto combinado (papi ⊆ papifutbol).
class BusquedaTexto {
  BusquedaTexto._();

  static List<String> tokens(String query) {
    final n = TextoProducto.normalizar(query);
    if (n.isEmpty) return const [];
    return n
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  /// Une campos y normaliza (minúsculas, sin acentos).
  static String haystack(Iterable<String?> campos) {
    return TextoProducto.normalizar(
      campos
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' '),
    );
  }

  /// True si [query] está vacío o todos sus tokens están en [campos].
  static bool coincide(String query, Iterable<String?> campos) {
    final toks = tokens(query);
    if (toks.isEmpty) return true;
    final h = haystack(campos);
    if (h.isEmpty) return false;
    return toks.every(h.contains);
  }

  /// Variante para mapas (búsqueda global / filas SQL).
  static bool coincideMapa(
    String query,
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    return coincide(
      query,
      keys.map((k) => row[k]?.toString()),
    );
  }
}
