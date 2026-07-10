class RemitoDetalle {
  int? id;

  int remitoId;
  int productoId;
  
  int cantidad;
  double precioUnitario;
  double subtotal;

  RemitoDetalle({
    this.id,
    required this.remitoId,
    required this.productoId,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'remitoId': remitoId,
      'productoId': productoId,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'subtotal': subtotal,
    };
  }

  factory RemitoDetalle.fromMap(Map<String, dynamic> map) {
    return RemitoDetalle(
      id: map['id'],
      remitoId: map['remitoId'],
      productoId: map['productoId'],
      cantidad: map['cantidad'] ?? 0,
      precioUnitario: (map['precioUnitario'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
    );
  }

  RemitoDetalle copyWith({
    int? id,
    int? remitoId,
    int? productoId,
    int? cantidad,
    double? precioUnitario,
    double? subtotal,
  }) {
    return RemitoDetalle(
      id: id ?? this.id,
      remitoId: remitoId ?? this.remitoId,
      productoId: productoId ?? this.productoId,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      subtotal: subtotal ?? this.subtotal,
    );
  }
}
