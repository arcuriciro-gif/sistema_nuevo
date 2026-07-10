import 'dart:convert';

class Producto {
  int? id;

  String codigo;
  String codigoBarras;
  String descripcion;
  String marca;
  String categoria;
  String subcategoria;
  String modelo;
  String colorProducto;
  String talle;
  String unidadVenta;
  String proveedor;
  String ubicacion;

  int stock;
  int stockMinimo;

  double costo;
  double precio;
  double precio2;
  double precio3;
  double porcentajeGanancia;

  String observaciones;
  String notasInternas;
  String foto;
  List<String> fotos;

  /// Precios por lista (`listaId` -> precio). Las claves 1/2/3 reflejan precio/precio2/precio3.
  Map<String, double> preciosListas;

  /// IDs de listas con precio bloqueado manualmente.
  Set<String> preciosBloqueados;
  bool favorito;
  String? deletedAt;

  Producto({
    this.id,
    required this.codigo,
    this.codigoBarras = '',
    required this.descripcion,
    required this.marca,
    required this.categoria,
    this.subcategoria = '',
    this.modelo = '',
    this.colorProducto = '',
    this.talle = '',
    this.unidadVenta = 'UN',
    required this.proveedor,
    required this.ubicacion,
    required this.stock,
    this.stockMinimo = 0,
    required this.costo,
    required this.precio,
    this.precio2 = 0.0,
    this.precio3 = 0.0,
    this.porcentajeGanancia = 0.0,
    required this.observaciones,
    this.notasInternas = '',
    required this.foto,
    List<String>? fotos,
    Map<String, double>? preciosListas,
    Set<String>? preciosBloqueados,
    this.favorito = false,
    this.deletedAt,
  })  : fotos = fotos ?? const [],
        preciosListas = preciosListas ?? const {},
        preciosBloqueados = preciosBloqueados ?? const {};

  bool get estaEliminado => deletedAt != null && deletedAt!.isNotEmpty;

  double get margenPorcentaje {
    if (precio <= 0) return 0;
    return ((precio - costo) / precio) * 100;
  }

  List<String> get todasLasFotos {
    if (fotos.isNotEmpty) return fotos;
    if (foto.isNotEmpty) return [foto];
    return const [];
  }

  String get fotoPrincipal =>
      fotos.isNotEmpty ? fotos.first : foto;

  Map<String, dynamic> toMap() {
    final fotosNormalizadas = todasLasFotos;
    return {
      'id': id,
      'codigo': codigo,
      'codigo_barras': codigoBarras,
      'descripcion': descripcion,
      'marca': marca,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'modelo': modelo,
      'color_producto': colorProducto,
      'talle': talle,
      'unidad_venta': unidadVenta,
      'proveedor': proveedor,
      'ubicacion': ubicacion,
      'stock': stock,
      'stock_minimo': stockMinimo,
      'costo': costo,
      'precio': precio,
      'precio2': precio2,
      'precio3': precio3,
      'porcentaje_ganancia': porcentajeGanancia,
      'observaciones': observaciones,
      'notas_internas': notasInternas,
      'foto': fotoPrincipal,
      'fotos': jsonEncode(fotosNormalizadas),
      'precios_listas': jsonEncode(preciosListas),
      'precios_bloqueados': jsonEncode(preciosBloqueados.toList()),
      'favorito': favorito ? 1 : 0,
      'deleted_at': deletedAt,
    };
  }

  factory Producto.fromMap(Map<String, dynamic> map) {
    final fotos = _parseStringList(map['fotos']);
    final fotoLegacy = map['foto']?.toString() ?? '';
    final fotosFinal =
        fotos.isNotEmpty ? fotos : (fotoLegacy.isNotEmpty ? [fotoLegacy] : <String>[]);

    return Producto(
      id: map['id'],
      codigo: map['codigo'] ?? '',
      codigoBarras: map['codigo_barras'] ?? '',
      descripcion: map['descripcion'] ?? '',
      marca: map['marca'] ?? '',
      categoria: map['categoria'] ?? '',
      subcategoria: map['subcategoria'] ?? '',
      modelo: map['modelo'] ?? '',
      colorProducto: map['color_producto'] ?? '',
      talle: map['talle'] ?? '',
      unidadVenta: map['unidad_venta'] ?? 'UN',
      proveedor: map['proveedor'] ?? '',
      ubicacion: map['ubicacion'] ?? '',
      stock: map['stock'] ?? 0,
      stockMinimo: map['stock_minimo'] ?? 0,
      costo: (map['costo'] ?? 0).toDouble(),
      precio: (map['precio'] ?? 0).toDouble(),
      precio2: (map['precio2'] ?? 0).toDouble(),
      precio3: (map['precio3'] ?? 0).toDouble(),
      porcentajeGanancia: (map['porcentaje_ganancia'] ?? 0).toDouble(),
      observaciones: map['observaciones'] ?? '',
      notasInternas: map['notas_internas'] ?? '',
      foto: fotoLegacy,
      fotos: fotosFinal,
      preciosListas: _parsePreciosListas(map['precios_listas']),
      preciosBloqueados: _parseStringSet(map['precios_bloqueados']),
      favorito: (map['favorito'] ?? 0) == 1 || map['favorito'] == true,
      deletedAt: map['deleted_at']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final data = Map<String, dynamic>.from(toMap()..remove('id'));
    data['actualizadoEn'] = DateTime.now().toUtc().toIso8601String();
    return data;
  }

  factory Producto.fromFirestore(Map<String, dynamic> data, {String? docId}) {
    final map = Map<String, dynamic>.from(data);
    if (docId != null && map['codigo'] == null) {
      map['codigo'] = docId;
    }
    return Producto.fromMap(map);
  }

  Producto copyWith({
    int? id,
    String? codigo,
    String? codigoBarras,
    String? descripcion,
    String? marca,
    String? categoria,
    String? subcategoria,
    String? modelo,
    String? colorProducto,
    String? talle,
    String? unidadVenta,
    String? proveedor,
    String? ubicacion,
    int? stock,
    int? stockMinimo,
    double? costo,
    double? precio,
    double? precio2,
    double? precio3,
    double? porcentajeGanancia,
    String? observaciones,
    String? notasInternas,
    String? foto,
    List<String>? fotos,
    Map<String, double>? preciosListas,
    Set<String>? preciosBloqueados,
    bool? favorito,
    String? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Producto(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      descripcion: descripcion ?? this.descripcion,
      marca: marca ?? this.marca,
      categoria: categoria ?? this.categoria,
      subcategoria: subcategoria ?? this.subcategoria,
      modelo: modelo ?? this.modelo,
      colorProducto: colorProducto ?? this.colorProducto,
      talle: talle ?? this.talle,
      unidadVenta: unidadVenta ?? this.unidadVenta,
      proveedor: proveedor ?? this.proveedor,
      ubicacion: ubicacion ?? this.ubicacion,
      stock: stock ?? this.stock,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      costo: costo ?? this.costo,
      precio: precio ?? this.precio,
      precio2: precio2 ?? this.precio2,
      precio3: precio3 ?? this.precio3,
      porcentajeGanancia: porcentajeGanancia ?? this.porcentajeGanancia,
      observaciones: observaciones ?? this.observaciones,
      notasInternas: notasInternas ?? this.notasInternas,
      foto: foto ?? this.foto,
      fotos: fotos ?? this.fotos,
      preciosListas: preciosListas ?? this.preciosListas,
      preciosBloqueados: preciosBloqueados ?? this.preciosBloqueados,
      favorito: favorito ?? this.favorito,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {
        return [raw];
      }
    }
    return [];
  }

  static Set<String> _parseStringSet(dynamic raw) {
    return _parseStringList(raw).toSet();
  }

  static Map<String, double> _parsePreciosListas(dynamic raw) {
    if (raw == null) return {};
    Map<String, dynamic> decoded;
    if (raw is Map) {
      decoded = raw.map((k, v) => MapEntry(k.toString(), v));
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is! Map) return {};
        decoded = value.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {
        return {};
      }
    } else {
      return {};
    }
    return decoded.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
  }
}
