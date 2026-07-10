class VentaItem {
  int? id;
  int ventaId;
  int productoId;
  String productoDescripcion;
  int cantidad;
  double precio;
  double subtotal;

  VentaItem({
    this.id,
    required this.ventaId,
    required this.productoId,
    required this.productoDescripcion,
    required this.cantidad,
    required this.precio,
    required this.subtotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ventaId': ventaId,
      'productoId': productoId,
      'productoDescripcion': productoDescripcion,
      'cantidad': cantidad,
      'precio': precio,
      'subtotal': subtotal,
    };
  }

  factory VentaItem.fromMap(Map<String, dynamic> map) {
    return VentaItem(
      id: map['id'],
      ventaId: map['ventaId'],
      productoId: map['productoId'],
      productoDescripcion: map['productoDescripcion'] ?? '',
      cantidad: map['cantidad'] ?? 0,
      precio: (map['precio'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
    );
  }
}
