class Remito {
  int? id;

  String numero;
  DateTime fecha;
  String tipo; // 'entrada' o 'salida'
  
  String? proveedorId; // si es entrada
  String? clienteId;   // si es salida
  
  String estado; // 'pendiente', 'confirmado', 'anulado'
  String estadoPago; // 'pendiente', 'parcial', 'cobrado'
  double totalPagado;
  double saldoPendiente;
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
    this.totalPagado = 0,
    double? saldoPendiente,
    required this.observaciones,
    required this.total,
    this.descuento = 0.0,
  }) : saldoPendiente = saldoPendiente ?? total;

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
      'totalPagado': totalPagado,
      'saldoPendiente': saldoPendiente,
      'observaciones': observaciones,
      'total': total,
      'descuento': descuento,
    };
  }

  factory Remito.fromMap(Map<String, dynamic> map) {
    final total = (map['total'] ?? 0).toDouble();
    final pagado = (map['totalPagado'] ?? 0).toDouble();
    final saldoRaw = map['saldoPendiente'];
    final saldo = saldoRaw == null
        ? (total - pagado).clamp(0, total).toDouble()
        : (saldoRaw as num).toDouble();
    return Remito(
      id: map['id'],
      numero: map['numero'] ?? '',
      fecha: DateTime.parse(map['fecha']),
      tipo: map['tipo'] ?? 'entrada',
      proveedorId: map['proveedorId'],
      clienteId: map['clienteId']?.toString(),
      estado: map['estado'] ?? 'pendiente',
      estadoPago: map['estadoPago'] ?? 'pendiente',
      totalPagado: pagado,
      saldoPendiente: saldo,
      observaciones: map['observaciones'] ?? '',
      total: total,
      descuento: (map['descuento'] ?? 0).toDouble(),
    );
  }

  static String estadoDesdeMontos(double total, double pagado) {
    if (pagado <= 0.009) return 'pendiente';
    if (pagado >= total - 0.009) return 'cobrado';
    return 'parcial';
  }
}
