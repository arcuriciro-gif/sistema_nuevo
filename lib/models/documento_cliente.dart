class DocumentoCliente {
  final String id;
  final String clienteSyncId;
  final int? clienteId;
  final String clienteNombre;
  final String tipo; // remito | factura | presupuesto | otro
  final String numero;
  final String nombreArchivo;
  final String url;
  final String localPath;
  final String creadoPor;
  final DateTime fecha;

  const DocumentoCliente({
    required this.id,
    required this.clienteSyncId,
    this.clienteId,
    required this.clienteNombre,
    required this.tipo,
    required this.numero,
    required this.nombreArchivo,
    required this.url,
    this.localPath = '',
    required this.creadoPor,
    required this.fecha,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'clienteSyncId': clienteSyncId,
        'clienteId': clienteId,
        'clienteNombre': clienteNombre,
        'tipo': tipo,
        'numero': numero,
        'nombreArchivo': nombreArchivo,
        'url': url,
        'localPath': localPath,
        'creadoPor': creadoPor,
        'fecha': fecha.toIso8601String(),
      };

  Map<String, dynamic> toFirestore() => {
        ...toMap(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      };

  factory DocumentoCliente.fromMap(Map<String, dynamic> map) {
    return DocumentoCliente(
      id: map['id']?.toString() ?? '',
      clienteSyncId: map['clienteSyncId']?.toString() ?? '',
      clienteId: (map['clienteId'] as num?)?.toInt(),
      clienteNombre: map['clienteNombre']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'otro',
      numero: map['numero']?.toString() ?? '',
      nombreArchivo: map['nombreArchivo']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      localPath: map['localPath']?.toString() ?? '',
      creadoPor: map['creadoPor']?.toString() ?? '',
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  DocumentoCliente copyWith({String? url}) => DocumentoCliente(
        id: id,
        clienteSyncId: clienteSyncId,
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        tipo: tipo,
        numero: numero,
        nombreArchivo: nombreArchivo,
        url: url ?? this.url,
        localPath: localPath,
        creadoPor: creadoPor,
        fecha: fecha,
      );
}
