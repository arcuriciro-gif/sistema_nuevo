class RemitoDetalle {
  int? id;

  int remitoId;
  int productoId;

  int cantidad;
  double precioUnitario;
  double subtotal;
  double costoUnitario;
  double ganancia;

  RemitoDetalle({
    this.id,
    required this.remitoId,
    required this.productoId,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.costoUnitario = 0,
    double? ganancia,
  }) : ganancia = ganancia ?? (subtotal - (costoUnitario * cantidad));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'remitoId': remitoId,
      'productoId': productoId,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'subtotal': subtotal,
      'costoUnitario': costoUnitario,
      'ganancia': ganancia,
    };
  }

  factory RemitoDetalle.fromMap(Map<String, dynamic> map) {
    final cantidad = map['cantidad'] ?? 0;
    final precio = (map['precioUnitario'] ?? map['precio'] ?? 0).toDouble();
    final subtotal = (map['subtotal'] ?? 0).toDouble();
    final costo = (map['costoUnitario'] ?? 0).toDouble();
    final qty = cantidad is int ? cantidad : (cantidad as num).toInt();
    return RemitoDetalle(
      id: map['id'],
      remitoId: map['remitoId'],
      productoId: map['productoId'],
      cantidad: qty,
      precioUnitario: precio,
      subtotal: subtotal,
      costoUnitario: costo,
      ganancia: (map['ganancia'] as num?)?.toDouble() ??
          (subtotal - costo * qty),
    );
  }

  RemitoDetalle copyWith({
    int? id,
    int? remitoId,
    int? productoId,
    int? cantidad,
    double? precioUnitario,
    double? subtotal,
    double? costoUnitario,
    double? ganancia,
  }) {
    return RemitoDetalle(
      id: id ?? this.id,
      remitoId: remitoId ?? this.remitoId,
      productoId: productoId ?? this.productoId,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      subtotal: subtotal ?? this.subtotal,
      costoUnitario: costoUnitario ?? this.costoUnitario,
      ganancia: ganancia ?? this.ganancia,
    );
  }
}
