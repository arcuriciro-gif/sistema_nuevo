class PedidoItem {
  int? id;
  int pedidoId;
  int? productoId;
  String articulo;
  int cantidad;
  String color;
  String observaciones;
  int orden;

  PedidoItem({
    this.id,
    required this.pedidoId,
    this.productoId,
    required this.articulo,
    required this.cantidad,
    this.color = '',
    this.observaciones = '',
    this.orden = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pedidoId': pedidoId,
      'productoId': productoId,
      'articulo': articulo,
      'cantidad': cantidad,
      'color': color,
      'observaciones': observaciones,
      'orden': orden,
    };
  }

  factory PedidoItem.fromMap(Map<String, dynamic> map) {
    return PedidoItem(
      id: map['id'] as int?,
      pedidoId: (map['pedidoId'] as num?)?.toInt() ?? 0,
      productoId: (map['productoId'] as num?)?.toInt(),
      articulo: map['articulo']?.toString() ?? '',
      cantidad: (map['cantidad'] as num?)?.toInt() ?? 0,
      color: map['color']?.toString() ?? '',
      observaciones: map['observaciones']?.toString() ?? '',
      orden: (map['orden'] as num?)?.toInt() ?? 0,
    );
  }

  PedidoItem copyWith({
    int? id,
    int? pedidoId,
    int? productoId,
    String? articulo,
    int? cantidad,
    String? color,
    String? observaciones,
    int? orden,
  }) {
    return PedidoItem(
      id: id ?? this.id,
      pedidoId: pedidoId ?? this.pedidoId,
      productoId: productoId ?? this.productoId,
      articulo: articulo ?? this.articulo,
      cantidad: cantidad ?? this.cantidad,
      color: color ?? this.color,
      observaciones: observaciones ?? this.observaciones,
      orden: orden ?? this.orden,
    );
  }
}
