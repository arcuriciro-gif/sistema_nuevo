class Venta {
  int? id;
  /// 'factura_a' | 'factura_b' | 'factura_c' | 'remito'
  String tipo;
  String numero;
  int? clienteId;
  String? clienteNombre;
  DateTime fecha;
  double subtotal;
  double descuento;
  double iva;
  double total;
  /// 'confirmada' | 'anulada'
  String estado;
  /// 'pendiente' | 'cobrado' | 'parcial'
  String estadoPago;
  String observaciones;
  String? fechaCreacion;
  int? usuarioId;

  Venta({
    this.id,
    required this.tipo,
    required this.numero,
    this.clienteId,
    this.clienteNombre,
    required this.fecha,
    this.subtotal = 0,
    this.descuento = 0,
    this.iva = 0,
    this.total = 0,
    this.estado = 'confirmada',
    this.estadoPago = 'pendiente',
    this.observaciones = '',
    this.fechaCreacion,
    this.usuarioId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'numero': numero,
      'clienteId': clienteId,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'descuento': descuento,
      'iva': iva,
      'estado': estado,
      'estadoPago': estadoPago,
      'observaciones': observaciones,
      'fechaCreacion': fechaCreacion ?? DateTime.now().toIso8601String(),
      'usuarioId': usuarioId,
    };
  }

  factory Venta.fromMap(Map<String, dynamic> map) {
    return Venta(
      id: map['id'],
      tipo: map['tipo'] ?? 'factura_b',
      numero: map['numero'] ?? '',
      clienteId: map['clienteId'],
      clienteNombre: map['clienteNombre'],
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
      subtotal: (map['subtotal'] ?? (map['total'] ?? 0)).toDouble(),
      descuento: (map['descuento'] ?? 0).toDouble(),
      iva: (map['iva'] ?? 0).toDouble(),
      total: (map['total'] ?? 0).toDouble(),
      estado: map['estado'] ?? 'confirmada',
      estadoPago: map['estadoPago'] ?? 'pendiente',
      observaciones: map['observaciones'] ?? '',
      fechaCreacion: map['fechaCreacion'],
      usuarioId: map['usuarioId'],
    );
  }

  String get tipoLabel {
    switch (tipo) {
      case 'factura_a':
        return 'Factura A';
      case 'factura_b':
        return 'Factura B';
      case 'factura_c':
        return 'Factura C';
      default:
        return 'Ticket / Remito';
    }
  }
}
