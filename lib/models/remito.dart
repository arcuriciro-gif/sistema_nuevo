class Remito {
  int? id;

  String numero;
  DateTime fecha;
  String tipo; // 'entrada' o 'salida'
  
  String? proveedorId; // si es entrada
  String? clienteId;   // si es salida
  
  String estado; // 'pendiente', 'confirmado', 'anulado'
  String estadoPago; // 'pendiente', 'parcial', 'cobrado'
  String observaciones;

  double total;
  double descuento;

  Remito({
    this.id,
    required this.numero,
    required this.fecha,
    required this.tipo,
    this.proveedorId,
    this.clienteId,
    required this.estado,
    this.estadoPago = 'pendiente',
    required this.observaciones,
    required this.total,
    this.descuento = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'fecha': fecha.toIso8601String(),
      'tipo': tipo,
      'proveedorId': proveedorId,
      'clienteId': clienteId,
      'estado': estado,
      'estadoPago': estadoPago,
      'observaciones': observaciones,
      'total': total,
      'descuento': descuento,
    };
  }

  factory Remito.fromMap(Map<String, dynamic> map) {
    return Remito(
      id: map['id'],
      numero: map['numero'] ?? '',
      fecha: DateTime.parse(map['fecha']),
      tipo: map['tipo'] ?? 'entrada',
      proveedorId: map['proveedorId'],
      clienteId: map['clienteId'],
      estado: map['estado'] ?? 'pendiente',
      estadoPago: map['estadoPago'] ?? 'pendiente',
      observaciones: map['observaciones'] ?? '',
      total: (map['total'] ?? 0).toDouble(),
      descuento: (map['descuento'] ?? 0).toDouble(),
    );
  }

  Remito copyWith({
    int? id,
    String? numero,
    DateTime? fecha,
    String? tipo,
    String? proveedorId,
    String? clienteId,
    String? estado,
    String? estadoPago,
    String? observaciones,
    double? total,
    double? descuento,
  }) {
    return Remito(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      fecha: fecha ?? this.fecha,
      tipo: tipo ?? this.tipo,
      proveedorId: proveedorId ?? this.proveedorId,
      clienteId: clienteId ?? this.clienteId,
      estado: estado ?? this.estado,
      estadoPago: estadoPago ?? this.estadoPago,
      observaciones: observaciones ?? this.observaciones,
      total: total ?? this.total,
      descuento: descuento ?? this.descuento,
    );
  }
}
