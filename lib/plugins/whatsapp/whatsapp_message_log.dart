class WhatsappMessageLog {
  final int? id;
  final int? clienteId;
  final String telefono;
  final String cuerpo;
  final String modo; // api | deeplink | template
  final String estado; // ok | error | abierto
  final String error;
  final String waMessageId;
  final DateTime fecha;

  const WhatsappMessageLog({
    this.id,
    this.clienteId,
    required this.telefono,
    required this.cuerpo,
    required this.modo,
    required this.estado,
    this.error = '',
    this.waMessageId = '',
    required this.fecha,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'clienteId': clienteId,
        'telefono': telefono,
        'cuerpo': cuerpo,
        'modo': modo,
        'estado': estado,
        'error': error,
        'waMessageId': waMessageId,
        'fecha': fecha.toIso8601String(),
      };

  factory WhatsappMessageLog.fromMap(Map<String, dynamic> m) =>
      WhatsappMessageLog(
        id: m['id'] as int?,
        clienteId: (m['clienteId'] as num?)?.toInt(),
        telefono: (m['telefono'] ?? '').toString(),
        cuerpo: (m['cuerpo'] ?? '').toString(),
        modo: (m['modo'] ?? '').toString(),
        estado: (m['estado'] ?? '').toString(),
        error: (m['error'] ?? '').toString(),
        waMessageId: (m['waMessageId'] ?? '').toString(),
        fecha: DateTime.tryParse('${m['fecha']}') ?? DateTime.now(),
      );
}
