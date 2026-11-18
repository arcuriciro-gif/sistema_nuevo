/// Seguimiento comercial local (sin sync).
class CrmSeguimiento {
  final int? id;
  final int clienteId;
  final String clienteNombre;
  final String titulo;
  final String nota;
  final String tipo; // cobro | reactivar | otro
  final DateTime fechaVencimiento;
  final String estado; // pendiente | hecho | cancelado
  final DateTime creadoEn;
  final DateTime? completadoEn;

  const CrmSeguimiento({
    this.id,
    required this.clienteId,
    required this.clienteNombre,
    required this.titulo,
    this.nota = '',
    this.tipo = 'otro',
    required this.fechaVencimiento,
    this.estado = 'pendiente',
    required this.creadoEn,
    this.completadoEn,
  });

  bool get vencido =>
      estado == 'pendiente' && fechaVencimiento.isBefore(DateTime.now());

  Map<String, dynamic> toMap() => {
        'id': id,
        'clienteId': clienteId,
        'clienteNombre': clienteNombre,
        'titulo': titulo,
        'nota': nota,
        'tipo': tipo,
        'fechaVencimiento': fechaVencimiento.toIso8601String(),
        'estado': estado,
        'creadoEn': creadoEn.toIso8601String(),
        'completadoEn': completadoEn?.toIso8601String() ?? '',
      };

  factory CrmSeguimiento.fromMap(Map<String, dynamic> m) => CrmSeguimiento(
        id: m['id'] as int?,
        clienteId: (m['clienteId'] as num).toInt(),
        clienteNombre: (m['clienteNombre'] ?? '').toString(),
        titulo: (m['titulo'] ?? '').toString(),
        nota: (m['nota'] ?? '').toString(),
        tipo: (m['tipo'] ?? 'otro').toString(),
        fechaVencimiento:
            DateTime.tryParse('${m['fechaVencimiento']}') ?? DateTime.now(),
        estado: (m['estado'] ?? 'pendiente').toString(),
        creadoEn: DateTime.tryParse('${m['creadoEn']}') ?? DateTime.now(),
        completadoEn: () {
          final s = (m['completadoEn'] ?? '').toString();
          if (s.isEmpty) return null;
          return DateTime.tryParse(s);
        }(),
      );

  CrmSeguimiento copyWith({
    int? id,
    String? titulo,
    String? nota,
    String? tipo,
    DateTime? fechaVencimiento,
    String? estado,
    DateTime? completadoEn,
  }) =>
      CrmSeguimiento(
        id: id ?? this.id,
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        titulo: titulo ?? this.titulo,
        nota: nota ?? this.nota,
        tipo: tipo ?? this.tipo,
        fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
        estado: estado ?? this.estado,
        creadoEn: creadoEn,
        completadoEn: completadoEn ?? this.completadoEn,
      );
}
