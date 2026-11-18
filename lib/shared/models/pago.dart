class Pago {
  int? id;
  int? ventaId;
  int? remitoId;
  int? clienteId;
  DateTime fecha;
  double monto;
  String medioPago;
  String observaciones;
  String? ventaNumero;
  String? remitoNumero;
  String? clienteNombre;

  Pago({
    this.id,
    this.ventaId,
    this.remitoId,
    this.clienteId,
    required this.fecha,
    required this.monto,
    this.medioPago = 'efectivo',
    this.observaciones = '',
    this.ventaNumero,
    this.remitoNumero,
    this.clienteNombre,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ventaId': ventaId,
      'remitoId': remitoId,
      'clienteId': clienteId,
      'fecha': fecha.toIso8601String(),
      'monto': monto,
      'medioPago': medioPago,
      'observaciones': observaciones,
    };
  }

  factory Pago.fromMap(Map<String, dynamic> map) {
    return Pago(
      id: map['id'] as int?,
      ventaId: (map['ventaId'] as num?)?.toInt(),
      remitoId: (map['remitoId'] as num?)?.toInt(),
      clienteId: map['clienteId'] as int?,
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      monto: (map['monto'] as num?)?.toDouble() ?? 0,
      medioPago: map['medioPago']?.toString() ?? 'efectivo',
      observaciones: map['observaciones']?.toString() ?? '',
      ventaNumero: map['ventaNumero']?.toString(),
      remitoNumero: map['remitoNumero']?.toString(),
      clienteNombre: map['clienteNombre']?.toString(),
    );
  }

  static const mediosPago = [
    'efectivo',
    'transferencia',
    'tarjeta',
    'cheque',
    'otro',
  ];

  static String labelMedio(String medio) {
    switch (medio) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      case 'tarjeta':
        return 'Tarjeta';
      case 'cheque':
        return 'Cheque';
      default:
        return 'Otro';
    }
  }

  String get comprobanteLabel {
    if (remitoNumero != null && remitoNumero!.isNotEmpty) {
      return 'Remito $remitoNumero';
    }
    if (ventaNumero != null && ventaNumero!.isNotEmpty) {
      return 'Comp. $ventaNumero';
    }
    if (remitoId != null) return 'Remito #$remitoId';
    if (ventaId != null) return 'Comp. #$ventaId';
    return 'Pago';
  }
}
