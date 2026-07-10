class Compra {
  int? id;
  int? proveedorId;
  String proveedorNombre;
  String numero;
  String factura;
  DateTime fecha;
  double total;
  double descuento;
  double iva;
  String observaciones;
  DateTime? fechaCreacion;
  String estado;

  Compra({
    this.id,
    this.proveedorId,
    required this.proveedorNombre,
    required this.numero,
    this.factura = '',
    required this.fecha,
    required this.total,
    this.descuento = 0,
    this.iva = 0,
    this.observaciones = '',
    this.fechaCreacion,
    this.estado = 'confirmada',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'proveedorId': proveedorId,
      'proveedorNombre': proveedorNombre,
      'numero': numero,
      'factura': factura,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'descuento': descuento,
      'iva': iva,
      'observaciones': observaciones,
      'fechaCreacion': (fechaCreacion ?? DateTime.now()).toIso8601String(),
      'estado': estado,
    };
  }

  factory Compra.fromMap(Map<String, dynamic> map) {
    return Compra(
      id: map['id'],
      proveedorId: map['proveedorId'],
      proveedorNombre: map['proveedorNombre'] ?? '',
      numero: map['numero'] ?? '',
      factura: map['factura'] ?? '',
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
      total: (map['total'] ?? 0).toDouble(),
      descuento: (map['descuento'] ?? 0).toDouble(),
      iva: (map['iva'] ?? 0).toDouble(),
      observaciones: map['observaciones'] ?? '',
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'])
          : null,
      estado: map['estado'] ?? 'confirmada',
    );
  }

  Compra copyWith({
    int? id,
    int? proveedorId,
    String? proveedorNombre,
    String? numero,
    String? factura,
    DateTime? fecha,
    double? total,
    double? descuento,
    double? iva,
    String? observaciones,
    DateTime? fechaCreacion,
    String? estado,
  }) {
    return Compra(
      id: id ?? this.id,
      proveedorId: proveedorId ?? this.proveedorId,
      proveedorNombre: proveedorNombre ?? this.proveedorNombre,
      numero: numero ?? this.numero,
      factura: factura ?? this.factura,
      fecha: fecha ?? this.fecha,
      total: total ?? this.total,
      descuento: descuento ?? this.descuento,
      iva: iva ?? this.iva,
      observaciones: observaciones ?? this.observaciones,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      estado: estado ?? this.estado,
    );
  }
}
