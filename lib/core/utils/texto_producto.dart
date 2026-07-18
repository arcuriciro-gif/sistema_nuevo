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

  static const _stop = {
    'x',
    'par',
    'por',
    'en',
    'de',
    'la',
    'el',
    'los',
    'las',
    'un',
    'una',
    'y',
    'o',
    'con',
    'para',
    'mm',
    'mts',
    'mtr',
    'kg',
    'lt',
    'lts',
    'cc',
    'gr',
    'doc',
    'al',
    'del',
    'claro', // "gris claro" → color gris
    'art',
  };

  static const _colores = {
    'blanco',
    'negro',
    'azul',
    'rojo',
    'beige',
    'marron',
    'gris',
    'verde',
    'rosa',
    'nude',
    'camel',
    'suela',
    'crudo',
    'natural',
    'fluo',
    'vison',
    'habano',
    'amarillo',
    'bordo',
    'celeste',
    'marino',
    'caramelo',
    'grey',
    'avorio',
  };

  /// Abreviaturas frecuentes en PDFs de proveedor (Cuero Sur, etc.).
  static const _aliasColor = {
    'neg': 'negro',
    'nigro': 'negro',
    'bco': 'blanco',
    'bl': 'blanco',
    'bla': 'blanco',
    'az': 'azul',
    'roj': 'rojo',
    'marr': 'marron',
    'mar': 'marron',
  };

  /// Clave de familia para talles hermanos: mismo artículo + mismo color.
  /// No cruza PICTO CUERO con PICTO GAMUZ ni TERNA NEGRA con TERNA TOALLA.
  static String claveFamiliaHermanos(String descripcion, {String color = ''}) {
    final art = articuloBase(descripcion);
    final cols = coloresEnTexto('$descripcion $color');
    if (art.isEmpty) return '';
    if (cols.isEmpty) return art;
    final sorted = cols.toList()..sort();
    return '$art|${sorted.join('+')}';
  }

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
    // Abreviaturas de color → forma canónica (NEG → negro).
    t = t
        .split(' ')
        .map((w) => _aliasColor[w] ?? w)
        .join(' ');
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

  /// Par consecutivo compacto tipo "3435" → 34-35, "4041" → 40-41.
  static ({int a, int b})? _parCompacto(String cuatroDigitos) {
    if (cuatroDigitos.length != 4) return null;
    final a = int.tryParse(cuatroDigitos.substring(0, 2));
    final b = int.tryParse(cuatroDigitos.substring(2, 4));
    if (a == null || b == null) return null;
    if (!_esTalleCalzado(a) || !_esTalleCalzado(b)) return null;
    // Pares de corrida típicos (34-35) o mismo talle raro
    if (b == a || b == a + 1) return (a: a, b: b);
    return null;
  }

  static Set<String> tokensSignificativos(String textoNormalizado) {
    return textoNormalizado
        .split(' ')
        .where((t) => t.length > 1 && !_stop.contains(t))
        // Ignorar talles sueltos (35, 39…) para emparejar modelo Leal vs stock por talle.
        .where((t) {
          final n = int.tryParse(t);
          if (n != null && _esTalleCalzado(n)) return false;
          return true;
        })
        .toSet();
  }

  /// True si el modelo/color del proveedor calza con el local.
  /// - Compara el "núcleo" sin colores (febo running ⊆ febo running goma)
  /// - Si ambos tienen color, debe haber intersección (sirve multi-color JK)
  static bool coincidePorTokens(String proveedor, String local) {
    final a = tokensSignificativos(normalizar(proveedor));
    final b = tokensSignificativos(normalizar(local));
    if (a.isEmpty || b.isEmpty) return false;

    final ca = a.intersection(_colores);
    final cb = b.intersection(_colores);
    final aCore = a.difference(_colores);
    final bCore = b.difference(_colores);

    if (ca.isNotEmpty && cb.isNotEmpty && ca.intersection(cb).isEmpty) {
      return false;
    }

    if (aCore.isEmpty) {
      // Solo colores: exigir intersección de color
      return ca.isEmpty || cb.isEmpty || ca.intersection(cb).isNotEmpty;
    }

    if (aCore.difference(bCore).isEmpty) return true; // core ⊆ local
    final comunes = aCore.intersection(bCore).length;
    final minNecesario =
        aCore.length <= 2 ? aCore.length : ((aCore.length * 0.75).ceil());
    return comunes >= minNecesario && comunes >= 2;
  }

  /// Extrae rango de talle en cualquier posición.
  /// Soporta:
  /// - "39-42", "35 al 41"
  /// - compacto JK: "3435/3839" → 34..39, "4647" → 46..47
  /// - "febo papifutbol 39-42 blanco"
  static ({String base, int? desde, int? hasta}) parsearRangoTalle(
    String descripcion,
  ) {
    var n = normalizar(descripcion);

    // 1) Compacto tipo Running: 3435/3839 o 4041/4445 o 4647
    final compactos = <({int a, int b})>[];
    final compactRe = RegExp(r'\b(\d{4})(?:\s*/\s*(\d{4}))?\b');
    final compactMatches = compactRe.allMatches(n).toList();
    for (final m in compactMatches) {
      final p1 = _parCompacto(m.group(1)!);
      if (p1 == null) continue;
      compactos.add(p1);
      if (m.group(2) != null) {
        final p2 = _parCompacto(m.group(2)!);
        if (p2 != null) compactos.add(p2);
      }
    }
    if (compactos.isNotEmpty) {
      final desde = compactos.map((p) => p.a).reduce((a, b) => a < b ? a : b);
      final hasta = compactos.map((p) => p.b).reduce((a, b) => a > b ? a : b);
      var base = n;
      for (final m in compactMatches.reversed) {
        final p1 = _parCompacto(m.group(1)!);
        if (p1 == null) continue;
        base = base.replaceFirst(m.group(0)!, ' ');
      }
      base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (hasta - desde <= 20) {
        return (base: base, desde: desde, hasta: hasta);
      }
    }

    // 2) Rango clásico 39-42 en cualquier posición
    final matches = RegExp(r'\b(\d{2})\s*-\s*(\d{2})\b').allMatches(n);
    for (final m in matches) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) continue;
      if (!_esTalleCalzado(a) || !_esTalleCalzado(b)) continue;
      final desde = a <= b ? a : b;
      final hasta = a <= b ? b : a;
      if (hasta - desde > 15) continue;

      final base =
          n.replaceFirst(m.group(0)!, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return (base: base, desde: desde, hasta: hasta);
    }

    return (base: n, desde: null, hasta: null);
  }

  /// ¿El producto local cae dentro del rango del proveedor?
  /// Soporta talle suelto (40) o par local (34-35).
  static bool localEnRangoProveedor({
    required String descripcionLocal,
    String colorLocal = '',
    String talleLocal = '',
    required int desde,
    required int hasta,
  }) {
    final t = parsearTalle(talleLocal);
    if (t != null && _esTalleCalzado(t)) {
      return t >= desde && t <= hasta;
    }

    final tFin = parsearTalleAlFinal(descripcionLocal) ??
        parsearTalleAlFinal('$descripcionLocal $colorLocal'.trim());
    if (tFin != null) {
      return tFin >= desde && tFin <= hasta;
    }

    final localRango = parsearRangoTalle(
      talleLocal.trim().isNotEmpty
          ? '$descripcionLocal $colorLocal $talleLocal'
          : '$descripcionLocal $colorLocal',
    );
    if (localRango.desde != null && localRango.hasta != null) {
      // El par/rango local debe estar contenido en el del proveedor.
      return localRango.desde! >= desde && localRango.hasta! <= hasta;
    }
    return false;
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
    if (RegExp(r'\d{4}\s*$').hasMatch(n)) return null;
    final m = RegExp(r'^(.*?)\s+(\d{2})\s*$').firstMatch(n);
    if (m == null) return null;
    final t = int.tryParse(m[2]!);
    if (t == null || !_esTalleCalzado(t)) return null;
    return t;
  }

  /// Quita talle final suelto o rango/par final de una descripción.
  static String quitarTalleFinal(String descripcion) {
    var n = normalizar(descripcion);
    // Quitar rango final 34-35
    n = n.replaceFirst(RegExp(r'\s+\d{2}\s*-\s*\d{2}\s*$'), '').trim();
    // Quitar compacto final 3435 o 3435/3839
    n = n.replaceFirst(RegExp(r'\s+\d{4}(?:\s*/\s*\d{4})?\s*$'), '').trim();
    final m = RegExp(r'^(.*?)\s+(\d{2})\s*$').firstMatch(n);
    if (m != null) {
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
    final base = normalizar([descripcion, color]
        .where((e) => e.trim().isNotEmpty)
        .join(' '));
    return quitarTalleFinal(base);
  }

  static const _ruidoArticulo = {
    'x',
    'par',
    'por',
    'en',
    'eva',
    'pu',
    'pve',
    'tr',
    'goma',
    'art',
    'mm',
    'mts',
    'mtr',
  };

  /// Artículo/modelo sin talle ni color.
  /// Sirve para listas tipo Leal/Profeta: un precio para todo el modelo
  /// (vos tenés artículo + color + talle separados solo por el stock).
  static String articuloBase(String texto) {
    var n = normalizar(texto);
    final rango = parsearRangoTalle(n);
    if (rango.desde != null) {
      n = rango.base;
    }
    n = quitarTalleFinal(n);
    // Quitar talles sueltos en cualquier posición (marilyn 39 negro → marilyn negro)
    n = n
        .split(' ')
        .where((t) {
          final v = int.tryParse(t);
          if (v != null && _esTalleCalzado(v)) return false;
          return true;
        })
        .join(' ');
    final parts = n
        .split(' ')
        .where((t) => t.isNotEmpty)
        .where((t) => !_colores.contains(t))
        .where((t) => !_ruidoArticulo.contains(t))
        .toList();
    return parts.join(' ').trim();
  }

  /// Color(es) mencionados en un texto de proveedor (si hay).
  static Set<String> coloresEnTexto(String texto) {
    return tokensSignificativos(normalizar(texto)).intersection(_colores);
  }

  /// ¿Mismo artículo? Comparación estricta (igualdad de núcleo).
  /// No usa umbrales flojos: evita cruzar modelos parecidos.
  static bool mismoArticulo(String a, String b) {
    final na = articuloBase(a);
    final nb = articuloBase(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final ta = tokensSignificativos(na).difference(_colores);
    final tb = tokensSignificativos(nb).difference(_colores);
    if (ta.isEmpty || tb.isEmpty) return false;
    return ta.length == tb.length && ta.difference(tb).isEmpty;
  }

  /// Local vs línea de proveedor con precio único por modelo
  /// (ignora color y talle del stock).
  static bool localEsMismoModeloPrecioUnico({
    required String descripcionProveedor,
    required String descripcionLocal,
    String modeloLocal = '',
  }) {
    final artProv = articuloBase(descripcionProveedor);
    if (artProv.isEmpty) return false;
    if (mismoArticulo(artProv, descripcionLocal)) return true;
    if (modeloLocal.trim().isNotEmpty &&
        mismoArticulo(artProv, modeloLocal)) {
      return true;
    }
    return false;
  }

  /// ¿El producto local comparte el color indicado por el proveedor?
  /// Si el proveedor no menciona color, no filtra.
  static bool localCoincideColorProveedor({
    required String descripcionLocal,
    required String colorLocal,
    required String textoProveedorSinTalle,
  }) {
    final coloresProv = coloresEnTexto(textoProveedorSinTalle);
    if (coloresProv.isEmpty) return true;

    final coloresLoc = coloresEnTexto('$descripcionLocal $colorLocal');
    if (coloresLoc.intersection(coloresProv).isNotEmpty) return true;

    final c = normalizar(colorLocal);
    if (c.isEmpty) {
      // Sin color en el local: no descartamos (puede ser genérico).
      return true;
    }
    if (coloresProv.contains(c)) return true;
    return coloresProv.any((p) => c == p || c.contains(p) || p.contains(c));
  }

  /// Compatible por campo proveedor del producto (si ambos tienen valor).
  static bool proveedorCompatible(String proveedorLista, String proveedorLocal) {
    final a = normalizar(proveedorLista);
    final b = normalizar(proveedorLocal);
    if (a.isEmpty || b.isEmpty) return true;
    if (a == b) return true;
    if (b.contains(a) || a.contains(b)) return true;
    return coincidePorTokens(a, b);
  }
}
