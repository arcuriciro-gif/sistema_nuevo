class Pedido {
  int? id;
  int? proveedorId;
  String proveedorNombre;
  String numero;
  DateTime fecha;
  String observaciones;
  String estado; // borrador | enviado | cerrado
  DateTime? fechaCreacion;
  DateTime? fechaActualizacion;

  Pedido({
    this.id,
    this.proveedorId,
    required this.proveedorNombre,
    required this.numero,
    required this.fecha,
    this.observaciones = '',
    this.estado = 'borrador',
    this.fechaCreacion,
    this.fechaActualizacion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'proveedorId': proveedorId,
      'proveedorNombre': proveedorNombre,
      'numero': numero,
      'fecha': fecha.toIso8601String(),
      'observaciones': observaciones,
      'estado': estado,
      'fechaCreacion': (fechaCreacion ?? DateTime.now()).toIso8601String(),
      'fechaActualizacion':
          (fechaActualizacion ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Pedido.fromMap(Map<String, dynamic> map) {
    return Pedido(
      id: map['id'] as int?,
      proveedorId: map['proveedorId'] as int?,
      proveedorNombre: map['proveedorNombre']?.toString() ?? '',
      numero: map['numero']?.toString() ?? '',
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      observaciones: map['observaciones']?.toString() ?? '',
      estado: map['estado']?.toString() ?? 'borrador',
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'].toString())
          : null,
      fechaActualizacion: map['fechaActualizacion'] != null
          ? DateTime.tryParse(map['fechaActualizacion'].toString())
          : null,
    );
  }

  Pedido copyWith({
    int? id,
    int? proveedorId,
    String? proveedorNombre,
    String? numero,
    DateTime? fecha,
    String? observaciones,
    String? estado,
    DateTime? fechaCreacion,
    DateTime? fechaActualizacion,
  }) {
    return Pedido(
      id: id ?? this.id,
      proveedorId: proveedorId ?? this.proveedorId,
      proveedorNombre: proveedorNombre ?? this.proveedorNombre,
      numero: numero ?? this.numero,
      fecha: fecha ?? this.fecha,
      observaciones: observaciones ?? this.observaciones,
      estado: estado ?? this.estado,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }
}
