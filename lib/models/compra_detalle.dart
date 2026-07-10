class CompraDetalle {
  int? id;

  int compraId;
  int productoId;
  String productoDescripcion;

  int cantidad;
  double costo;
  double subtotal;

  CompraDetalle({
    this.id,
    required this.compraId,
    required this.productoId,
    required this.productoDescripcion,
    required this.cantidad,
    required this.costo,
    required this.subtotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'compraId': compraId,
      'productoId': productoId,
      'productoDescripcion': productoDescripcion,
      'cantidad': cantidad,
      'costo': costo,
      'subtotal': subtotal,
    };
  }

  factory CompraDetalle.fromMap(Map<String, dynamic> map) {
    return CompraDetalle(
      id: map['id'],
      compraId: map['compraId'],
      productoId: map['productoId'],
      productoDescripcion: map['productoDescripcion'] ?? '',
      cantidad: map['cantidad'] ?? 0,
      costo: (map['costo'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
    );
  }

  CompraDetalle copyWith({
    int? id,
    int? compraId,
    int? productoId,
    String? productoDescripcion,
    int? cantidad,
    double? costo,
    double? subtotal,
  }) {
    return CompraDetalle(
      id: id ?? this.id,
      compraId: compraId ?? this.compraId,
      productoId: productoId ?? this.productoId,
      productoDescripcion: productoDescripcion ?? this.productoDescripcion,
      cantidad: cantidad ?? this.cantidad,
      costo: costo ?? this.costo,
      subtotal: subtotal ?? this.subtotal,
    );
  }
}
