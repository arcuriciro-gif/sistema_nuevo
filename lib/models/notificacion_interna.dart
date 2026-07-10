class NotificacionInterna {
  final String id;
  final String usuarioDestino;
  final String tipo;
  // mensaje | stock | cobro | venta | remito | presupuesto | cliente | sistema | archivo
  final String titulo;
  final String cuerpo;
  final String? conversacionId;
  final String? entidadTipo;
  final String? entidadId;
  final DateTime fecha;
  final bool leida;

  const NotificacionInterna({
    required this.id,
    required this.usuarioDestino,
    required this.tipo,
    required this.titulo,
    required this.cuerpo,
    this.conversacionId,
    this.entidadTipo,
    this.entidadId,
    required this.fecha,
    this.leida = false,
  });

  IconDataLike get iconHint => switch (tipo) {
        'mensaje' || 'archivo' => 'chat',
        'stock' => 'stock',
        'cobro' => 'cobro',
        'venta' => 'venta',
        'remito' => 'remito',
        'presupuesto' => 'presupuesto',
        'cliente' => 'cliente',
        _ => 'sistema',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'usuarioDestino': usuarioDestino,
        'tipo': tipo,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'conversacionId': conversacionId,
        'entidadTipo': entidadTipo,
        'entidadId': entidadId,
        'fecha': fecha.toIso8601String(),
        'leida': leida ? 1 : 0,
      };

  Map<String, dynamic> toFirestore() => {
        'usuarioDestino': usuarioDestino,
        'tipo': tipo,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'conversacionId': conversacionId,
        'entidadTipo': entidadTipo,
        'entidadId': entidadId,
        'fecha': fecha.toUtc().toIso8601String(),
        'leida': leida,
      };

  factory NotificacionInterna.fromMap(Map<String, dynamic> map) {
    return NotificacionInterna(
      id: map['id']?.toString() ?? '',
      usuarioDestino: map['usuarioDestino']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'sistema',
      titulo: map['titulo']?.toString() ?? '',
      cuerpo: map['cuerpo']?.toString() ?? '',
      conversacionId: map['conversacionId']?.toString(),
      entidadTipo: map['entidadTipo']?.toString(),
      entidadId: map['entidadId']?.toString(),
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      leida: map['leida'] == true || map['leida'] == 1,
    );
  }

  factory NotificacionInterna.fromFirestore(
    Map<String, dynamic> data, {
    required String id,
  }) {
    return NotificacionInterna.fromMap({...data, 'id': id});
  }
}

/// Hint tipado sin importar Flutter en el modelo.
typedef IconDataLike = String;
