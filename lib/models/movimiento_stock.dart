class MovimientoStock {
  int? id;
  int productoId;
  String tipo;
  int cantidad;
  DateTime fecha;
  String? remitoId;
  String motivo;
  String usuario;
  int stockAnterior;
  int stockNuevo;

  MovimientoStock({
    this.id,
    required this.productoId,
    required this.tipo,
    required this.cantidad,
    required this.fecha,
    this.remitoId,
    required this.motivo,
    this.usuario = '',
    this.stockAnterior = 0,
    this.stockNuevo = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'productoId': productoId,
      'tipo': tipo,
      'cantidad': cantidad,
      'fecha': fecha.toIso8601String(),
      'remitoId': remitoId,
      'motivo': motivo,
      'usuario': usuario,
      'stockAnterior': stockAnterior,
      'stockNuevo': stockNuevo,
    };
  }

  factory MovimientoStock.fromMap(Map<String, dynamic> map) {
    return MovimientoStock(
      id: map['id'],
      productoId: map['productoId'],
      tipo: map['tipo'] ?? 'entrada',
      cantidad: map['cantidad'] ?? 0,
      fecha: DateTime.parse(map['fecha']),
      remitoId: map['remitoId'],
      motivo: map['motivo'] ?? '',
      usuario: map['usuario'] ?? '',
      stockAnterior: map['stockAnterior'] ?? 0,
      stockNuevo: map['stockNuevo'] ?? 0,
    );
  }

  MovimientoStock copyWith({
    int? id,
    int? productoId,
    String? tipo,
    int? cantidad,
    DateTime? fecha,
    String? remitoId,
    String? motivo,
    String? usuario,
    int? stockAnterior,
    int? stockNuevo,
  }) {
    return MovimientoStock(
      id: id ?? this.id,
      productoId: productoId ?? this.productoId,
      tipo: tipo ?? this.tipo,
      cantidad: cantidad ?? this.cantidad,
      fecha: fecha ?? this.fecha,
      remitoId: remitoId ?? this.remitoId,
      motivo: motivo ?? this.motivo,
      usuario: usuario ?? this.usuario,
      stockAnterior: stockAnterior ?? this.stockAnterior,
      stockNuevo: stockNuevo ?? this.stockNuevo,
    );
  }
}
