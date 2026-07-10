class Venta {
  int? id;
  /// 'factura_a' | 'factura_b' | 'factura_c' | 'presupuesto' | 'nota_entrega' | 'comprobante_interno' | 'remito'
  String tipo;
  String numero;
  int? clienteId;
  String? clienteNombre;
  DateTime fecha;
  DateTime? fechaVencimiento;
  double subtotal;
  double descuento;
  double iva;
  /// Total de la venta (totalVenta).
  double total;
  double totalPagado;
  double saldoPendiente;
  /// 'confirmada' | 'anulada'
  String estado;
  /// 'pendiente' | 'parcial' | 'cobrado'
  String estadoPago;
  /// 'no_aplica' | 'pendiente_afip' | 'pendiente_config' | 'autorizada' | 'rechazada'
  String estadoAfip;
  String cae;
  DateTime? caeVencimiento;
  int puntoVenta;
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
    this.fechaVencimiento,
    this.subtotal = 0,
    this.descuento = 0,
    this.iva = 0,
    this.total = 0,
    this.totalPagado = 0,
    double? saldoPendiente,
    this.estado = 'confirmada',
    this.estadoPago = 'pendiente',
    this.estadoAfip = 'no_aplica',
    this.cae = '',
    this.caeVencimiento,
    this.puntoVenta = 0,
    this.observaciones = '',
    this.fechaCreacion,
    this.usuarioId,
  }) : saldoPendiente = saldoPendiente ?? total;

  /// Alias pedido en el requerimiento.
  double get totalVenta => total;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'numero': numero,
      'clienteId': clienteId,
      'fecha': fecha.toIso8601String(),
      'fechaVencimiento': fechaVencimiento?.toIso8601String(),
      'total': total,
      'descuento': descuento,
      'iva': iva,
      'estado': estado,
      'estadoPago': estadoPago,
      'totalPagado': totalPagado,
      'saldoPendiente': saldoPendiente,
      'estadoAfip': estadoAfip,
      'cae': cae,
      'caeVencimiento': caeVencimiento?.toIso8601String(),
      'puntoVenta': puntoVenta,
      'observaciones': observaciones,
      'fechaCreacion': fechaCreacion ?? DateTime.now().toIso8601String(),
      'usuarioId': usuarioId,
    };
  }

  Map<String, dynamic> toFirestore() {
    final data = Map<String, dynamic>.from(toMap()..remove('id'));
    data['clienteNombre'] = clienteNombre;
    data['actualizadoEn'] = DateTime.now().toUtc().toIso8601String();
    return data;
  }

  factory Venta.fromMap(Map<String, dynamic> map) {
    final total = (map['total'] ?? 0).toDouble();
    final pagado = (map['totalPagado'] ?? 0).toDouble();
    final saldo = map['saldoPendiente'] != null
        ? (map['saldoPendiente'] as num).toDouble()
        : (total - pagado);
    return Venta(
      id: map['id'],
      tipo: map['tipo'] ?? 'factura_b',
      numero: map['numero'] ?? '',
      clienteId: map['clienteId'],
      clienteNombre: map['clienteNombre'],
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
      fechaVencimiento: DateTime.tryParse(map['fechaVencimiento']?.toString() ?? ''),
      subtotal: (map['subtotal'] ?? (map['total'] ?? 0)).toDouble(),
      descuento: (map['descuento'] ?? 0).toDouble(),
      iva: (map['iva'] ?? 0).toDouble(),
      total: total,
      totalPagado: pagado,
      saldoPendiente: saldo,
      estado: map['estado'] ?? 'confirmada',
      estadoPago: map['estadoPago'] ?? 'pendiente',
      estadoAfip: map['estadoAfip'] ?? 'no_aplica',
      cae: map['cae']?.toString() ?? '',
      caeVencimiento: DateTime.tryParse(map['caeVencimiento']?.toString() ?? ''),
      puntoVenta: (map['puntoVenta'] as int?) ?? 0,
      observaciones: map['observaciones'] ?? '',
      fechaCreacion: map['fechaCreacion'],
      usuarioId: map['usuarioId'],
    );
  }

  static String calcularEstadoPago(double total, double pagado) {
    if (pagado <= 0.009) return 'pendiente';
    if (pagado + 0.009 >= total) return 'cobrado';
    return 'parcial';
  }

  String get estadoPagoLabel {
    switch (estadoPago) {
      case 'cobrado':
        return 'Pagada';
      case 'parcial':
        return 'Pago parcial';
      default:
        return 'Pendiente';
    }
  }

  String get tipoLabel {
    switch (tipo) {
      case 'factura_a':
        return 'Factura A';
      case 'factura_b':
        return 'Factura B';
      case 'factura_c':
        return 'Factura C';
      case 'presupuesto':
        return 'Presupuesto';
      case 'nota_entrega':
        return 'Nota de entrega';
      case 'comprobante_interno':
        return 'Comprobante interno';
      default:
        return 'Ticket / Remito';
    }
  }

  String get tipoDocumentoPdf {
    switch (tipo) {
      case 'factura_a':
        return 'FACTURA A';
      case 'factura_b':
        return 'FACTURA B';
      case 'factura_c':
        return 'FACTURA C';
      case 'presupuesto':
        return 'PRESUPUESTO';
      case 'nota_entrega':
        return 'NOTA DE ENTREGA';
      case 'comprobante_interno':
        return 'COMPROBANTE INTERNO';
      default:
        return tipoLabel.toUpperCase();
    }
  }

  bool get esFactura =>
      tipo == 'factura_a' || tipo == 'factura_b' || tipo == 'factura_c';
}
