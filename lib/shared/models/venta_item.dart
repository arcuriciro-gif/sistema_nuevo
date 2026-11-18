class VentaItem {
  int? id;
  int ventaId;
  int productoId;
  String productoDescripcion;
  int cantidad;
  double precio;
  double subtotal;
  double costoUnitario;
  double ganancia;

  VentaItem({
    this.id,
    required this.ventaId,
    required this.productoId,
    required this.productoDescripcion,
    required this.cantidad,
    required this.precio,
    required this.subtotal,
    this.costoUnitario = 0,
    double? ganancia,
  }) : ganancia = ganancia ?? (subtotal - (costoUnitario * cantidad));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ventaId': ventaId,
      'productoId': productoId,
      'productoDescripcion': productoDescripcion,
      'cantidad': cantidad,
      'precio': precio,
      'subtotal': subtotal,
      'costoUnitario': costoUnitario,
      'ganancia': ganancia,
    };
  }

  factory VentaItem.fromMap(Map<String, dynamic> map) {
    final cantidad = map['cantidad'] ?? 0;
    final precio = (map['precio'] ?? 0).toDouble();
    final subtotal = (map['subtotal'] ?? 0).toDouble();
    final costo = (map['costoUnitario'] ?? 0).toDouble();
    return VentaItem(
      id: map['id'],
      ventaId: map['ventaId'],
      productoId: map['productoId'],
      productoDescripcion: map['productoDescripcion'] ?? '',
      cantidad: cantidad is int ? cantidad : (cantidad as num).toInt(),
      precio: precio,
      subtotal: subtotal,
      costoUnitario: costo,
      ganancia: (map['ganancia'] as num?)?.toDouble() ??
          (subtotal - costo * (cantidad as num).toDouble()),
    );
  }
}
