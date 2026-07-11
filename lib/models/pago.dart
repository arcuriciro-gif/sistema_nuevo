class Pago {
  int? id;
  int ventaId;
  int? clienteId;
  DateTime fecha;
  double monto;
  String medioPago;
  String observaciones;
  String? ventaNumero;
  String? clienteNombre;

  Pago({
    this.id,
    required this.ventaId,
    this.clienteId,
    required this.fecha,
    required this.monto,
    this.medioPago = 'efectivo',
    this.observaciones = '',
    this.ventaNumero,
    this.clienteNombre,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ventaId': ventaId,
      'clienteId': clienteId,
      'fecha': fecha.toIso8601String(),
      'monto': monto,
      'medioPago': medioPago,
      'observaciones': observaciones,
    };
  }

  factory Pago.fromMap(Map<String, dynamic> map) {
    return Pago(
      id: (map['id'] as num?)?.toInt(),
      ventaId: (map['ventaId'] as num?)?.toInt() ?? 0,
      clienteId: (map['clienteId'] as num?)?.toInt(),
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      monto: (map['monto'] as num?)?.toDouble() ?? 0,
      medioPago: map['medioPago']?.toString() ?? 'efectivo',
      observaciones: map['observaciones']?.toString() ?? '',
      ventaNumero: map['ventaNumero']?.toString(),
      clienteNombre: map['clienteNombre']?.toString(),
    );
  }

  static const mediosPago = [
    'efectivo',
    'transferencia',
    'tarjeta_debito',
    'tarjeta_credito',
    'cheque',
    'cuenta_corriente',
    'otro',
  ];

  static String labelMedio(String medio) {
    switch (medio) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      case 'tarjeta_debito':
        return 'Tarjeta débito';
      case 'tarjeta_credito':
        return 'Tarjeta crédito';
      case 'cheque':
        return 'Cheque';
      case 'cuenta_corriente':
        return 'Cuenta corriente';
      default:
        return 'Otro';
    }
  }
}
