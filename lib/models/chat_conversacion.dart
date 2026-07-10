import 'dart:convert';

class ChatConversacion {
  final String id;
  final String tipo; // dm | grupo
  final List<String> participantes;
  final Map<String, String> nombres;
  final String? titulo;
  final String ultimoMensaje;
  final DateTime? ultimoMensajeAt;
  final Map<String, int> noLeidos;
  final DateTime creadaAt;

  const ChatConversacion({
    required this.id,
    this.tipo = 'dm',
    required this.participantes,
    this.nombres = const {},
    this.titulo,
    this.ultimoMensaje = '',
    this.ultimoMensajeAt,
    this.noLeidos = const {},
    required this.creadaAt,
  });

  int noLeidosDe(String usuario) => noLeidos[usuario] ?? 0;

  String tituloPara(String yo) {
    if (titulo != null && titulo!.trim().isNotEmpty) return titulo!;
    if (tipo == 'grupo') return 'Grupo';
    final otros = participantes.where((p) => p != yo).toList();
    if (otros.isEmpty) return 'Yo';
    return otros.map((u) => nombres[u] ?? u).join(', ');
  }

  String inicialPara(String yo) {
    final t = tituloPara(yo);
    return t.isNotEmpty ? t[0].toUpperCase() : '?';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tipo': tipo,
        'participantes': jsonEncode(participantes),
        'nombres': jsonEncode(nombres),
        'titulo': titulo,
        'ultimoMensaje': ultimoMensaje,
        'ultimoMensajeAt': ultimoMensajeAt?.toIso8601String(),
        'noLeidos': jsonEncode(noLeidos),
        'creadaAt': creadaAt.toIso8601String(),
      };

  Map<String, dynamic> toFirestore() => {
        'tipo': tipo,
        'participantes': participantes,
        'nombres': nombres,
        'titulo': titulo,
        'ultimoMensaje': ultimoMensaje,
        'ultimoMensajeAt': ultimoMensajeAt?.toUtc().toIso8601String(),
        'noLeidos': noLeidos,
        'creadaAt': creadaAt.toUtc().toIso8601String(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      };

  factory ChatConversacion.fromMap(Map<String, dynamic> map) {
    List<String> parseList(dynamic raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is List) return d.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      return [];
    }

    Map<String, String> parseStringMap(dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      if (raw is String && raw.isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map) {
            return d.map((k, v) => MapEntry(k.toString(), v.toString()));
          }
        } catch (_) {}
      }
      return {};
    }

    Map<String, int> parseIntMap(dynamic raw) {
      if (raw is Map) {
        return raw.map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        );
      }
      if (raw is String && raw.isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map) {
            return d.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
            );
          }
        } catch (_) {}
      }
      return {};
    }

    return ChatConversacion(
      id: map['id']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'dm',
      participantes: parseList(map['participantes']),
      nombres: parseStringMap(map['nombres']),
      titulo: map['titulo']?.toString(),
      ultimoMensaje: map['ultimoMensaje']?.toString() ?? '',
      ultimoMensajeAt:
          DateTime.tryParse(map['ultimoMensajeAt']?.toString() ?? ''),
      noLeidos: parseIntMap(map['noLeidos']),
      creadaAt: DateTime.tryParse(map['creadaAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory ChatConversacion.fromFirestore(
    Map<String, dynamic> data, {
    required String id,
  }) {
    return ChatConversacion.fromMap({...data, 'id': id});
  }
}
