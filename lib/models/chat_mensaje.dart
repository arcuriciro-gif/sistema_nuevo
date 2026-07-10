import 'dart:convert';

/// Tipos de mensaje del módulo Comunicaciones.
class ChatMensajeTipo {
  static const texto = 'texto';
  static const imagen = 'imagen';
  static const archivo = 'archivo';
  static const compartido = 'compartido';
}

class ChatMensajeEstado {
  static const enviado = 'enviado';
  static const entregado = 'entregado';
  static const leido = 'leido';
}

class ChatCompartido {
  final String tipo; // producto | venta | remito | presupuesto | compra | cliente
  final String idRef;
  final String titulo;
  final String subtitulo;
  final Map<String, dynamic> datos;

  const ChatCompartido({
    required this.tipo,
    required this.idRef,
    required this.titulo,
    this.subtitulo = '',
    this.datos = const {},
  });

  Map<String, dynamic> toMap() => {
        'tipo': tipo,
        'idRef': idRef,
        'titulo': titulo,
        'subtitulo': subtitulo,
        'datos': datos,
      };

  factory ChatCompartido.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const ChatCompartido(tipo: '', idRef: '', titulo: '');
    }
    final datosRaw = map['datos'];
    return ChatCompartido(
      tipo: map['tipo']?.toString() ?? '',
      idRef: map['idRef']?.toString() ?? '',
      titulo: map['titulo']?.toString() ?? '',
      subtitulo: map['subtitulo']?.toString() ?? '',
      datos: datosRaw is Map
          ? Map<String, dynamic>.from(datosRaw)
          : <String, dynamic>{},
    );
  }
}

class ChatMensaje {
  final String id;
  final String conversacionId;
  final String autorUsuario;
  final String autorNombre;
  final String tipo;
  final String texto;
  final String? archivoPath;
  final String? archivoNombre;
  final String? archivoMime;
  final ChatCompartido? compartido;
  final DateTime fecha;
  final Map<String, String> estados;

  const ChatMensaje({
    required this.id,
    required this.conversacionId,
    required this.autorUsuario,
    required this.autorNombre,
    required this.tipo,
    this.texto = '',
    this.archivoPath,
    this.archivoNombre,
    this.archivoMime,
    this.compartido,
    required this.fecha,
    this.estados = const {},
  });

  bool get esMio => false; // resolved in UI with current user

  String estadoPara(String usuario) =>
      estados[usuario] ?? ChatMensajeEstado.enviado;

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversacionId': conversacionId,
        'autorUsuario': autorUsuario,
        'autorNombre': autorNombre,
        'tipo': tipo,
        'texto': texto,
        'archivoPath': archivoPath,
        'archivoNombre': archivoNombre,
        'archivoMime': archivoMime,
        'compartido': compartido == null ? null : jsonEncode(compartido!.toMap()),
        'fecha': fecha.toIso8601String(),
        'estados': jsonEncode(estados),
      };

  Map<String, dynamic> toFirestore() => {
        'autorUsuario': autorUsuario,
        'autorNombre': autorNombre,
        'tipo': tipo,
        'texto': texto,
        'archivoPath': archivoPath,
        'archivoNombre': archivoNombre,
        'archivoMime': archivoMime,
        'compartido': compartido?.toMap(),
        'fecha': fecha.toUtc().toIso8601String(),
        'estados': estados,
      };

  factory ChatMensaje.fromMap(Map<String, dynamic> map) {
    Map<String, String> estados = {};
    final rawEstados = map['estados'];
    if (rawEstados is Map) {
      estados = rawEstados.map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (rawEstados is String && rawEstados.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEstados);
        if (decoded is Map) {
          estados =
              decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    ChatCompartido? compartido;
    final rawComp = map['compartido'];
    if (rawComp is Map) {
      compartido = ChatCompartido.fromMap(Map<String, dynamic>.from(rawComp));
    } else if (rawComp is String && rawComp.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawComp);
        if (decoded is Map) {
          compartido =
              ChatCompartido.fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    return ChatMensaje(
      id: map['id']?.toString() ?? '',
      conversacionId: map['conversacionId']?.toString() ?? '',
      autorUsuario: map['autorUsuario']?.toString() ?? '',
      autorNombre: map['autorNombre']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? ChatMensajeTipo.texto,
      texto: map['texto']?.toString() ?? '',
      archivoPath: map['archivoPath']?.toString(),
      archivoNombre: map['archivoNombre']?.toString(),
      archivoMime: map['archivoMime']?.toString(),
      compartido: compartido,
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime.now(),
      estados: estados,
    );
  }

  factory ChatMensaje.fromFirestore(Map<String, dynamic> data, {required String id}) {
    return ChatMensaje.fromMap({...data, 'id': id});
  }
}
