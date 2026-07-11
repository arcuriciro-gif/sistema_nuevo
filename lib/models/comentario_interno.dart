class ComentarioInterno {
  final int? id;
  final String entidadTipo;
  // producto | cliente | venta | compra | remito | presupuesto | proveedor
  final String entidadId;
  final String usuario;
  final String nombre;
  final String texto;
  final DateTime fecha;
  final bool activo;

  const ComentarioInterno({
    this.id,
    required this.entidadTipo,
    required this.entidadId,
    required this.usuario,
    required this.nombre,
    required this.texto,
    required this.fecha,
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'entidadTipo': entidadTipo,
        'entidadId': entidadId,
        'usuario': usuario,
        'nombre': nombre,
        'texto': texto,
        'fecha': fecha.toUtc().toIso8601String(),
        'activo': activo ? 1 : 0,
      };

  factory ComentarioInterno.fromMap(Map<String, dynamic> map) {
    return ComentarioInterno(
      id: map['id'] as int?,
      entidadTipo: map['entidadTipo']?.toString() ?? '',
      entidadId: map['entidadId']?.toString() ?? '',
      usuario: map['usuario']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? '',
      texto: map['texto']?.toString() ?? '',
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      activo: map['activo'] == null || map['activo'] == 1 || map['activo'] == true,
    );
  }
}
