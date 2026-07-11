import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/sync/media_sync_service.dart';
import '../database/database_helper.dart';
import '../models/chat_conversacion.dart';
import '../models/chat_mensaje.dart';
import '../models/notificacion_interna.dart';
import '../models/usuario.dart';
import '../repositories/sqlite_usuario_repository.dart';
import 'auth_service.dart';

/// Chat interno + notificaciones (SQLite local + Firestore cuando hay Firebase).
class ComunicacionesService extends ChangeNotifier {
  ComunicacionesService._();
  static final ComunicacionesService instance = ComunicacionesService._();

  final _uuid = const Uuid();
  final _usuariosRepo = SqliteUsuarioRepository();
  StreamSubscription? _convSub;
  StreamSubscription? _notifSub;

  List<ChatConversacion> _conversaciones = [];
  List<NotificacionInterna> _notificaciones = [];
  int _mensajesSinLeer = 0;
  int _notifSinLeer = 0;

  List<ChatConversacion> get conversaciones => _conversaciones;
  List<NotificacionInterna> get notificaciones => _notificaciones;
  int get mensajesSinLeer => _mensajesSinLeer;
  int get notifSinLeer => _notifSinLeer;
  int get badgeTotal => _mensajesSinLeer + _notifSinLeer;

  String? get _yo => AuthService.instance.currentUser?.usuario;

  bool get _firebaseOk =>
      FirebaseBootstrap.isReady &&
      BackendConfigService.instance.firebaseEnabled &&
      AuthService.instance.currentUser != null;

  CollectionReference<Map<String, dynamic>>? get _chatsCol {
    if (!_firebaseOk) return null;
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('chats');
  }

  CollectionReference<Map<String, dynamic>>? get _notifCol {
    if (!_firebaseOk) return null;
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('notificaciones');
  }

  Future<void> iniciar() async {
    await refrescar();
    _escucharRemoto();
  }

  Future<void> detener() async {
    await _convSub?.cancel();
    await _notifSub?.cancel();
    _convSub = null;
    _notifSub = null;
  }

  void _escucharRemoto() {
    final yo = _yo;
    final chats = _chatsCol;
    final notifs = _notifCol;
    if (yo == null || chats == null) return;

    _convSub?.cancel();
    _convSub = chats
        .where('participantes', arrayContains: yo)
        .snapshots()
        .listen((snap) async {
      final list = snap.docs
          .map((d) => ChatConversacion.fromFirestore(d.data(), id: d.id))
          .toList()
        ..sort((a, b) {
          final fa = a.ultimoMensajeAt ?? a.creadaAt;
          final fb = b.ultimoMensajeAt ?? b.creadaAt;
          return fb.compareTo(fa);
        });
      for (final c in list) {
        await _upsertConversacionLocal(c);
      }
      await refrescar();
    }, onError: (e) => debugPrint('chats stream: $e'));

    if (notifs != null) {
      _notifSub?.cancel();
      _notifSub = notifs
          .where('usuarioDestino', isEqualTo: yo)
          .orderBy('fecha', descending: true)
          .limit(100)
          .snapshots()
          .listen((snap) async {
        final list = snap.docs
            .map((d) => NotificacionInterna.fromFirestore(d.data(), id: d.id))
            .toList();
        final db = await DatabaseHelper.instance.database;
        for (final n in list) {
          await db.insert(
            'notificaciones_internas',
            n.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await refrescar();
      }, onError: (e) => debugPrint('notif stream: $e'));
    }
  }

  Future<void> refrescar() async {
    final yo = _yo;
    if (yo == null) {
      _conversaciones = [];
      _notificaciones = [];
      _mensajesSinLeer = 0;
      _notifSinLeer = 0;
      notifyListeners();
      return;
    }

    final db = await DatabaseHelper.instance.database;
    final convRows = await db.query(
      'chat_conversaciones',
      orderBy: 'datetime(ultimoMensajeAt) DESC, datetime(creadaAt) DESC',
    );
    _conversaciones = convRows
        .map(ChatConversacion.fromMap)
        .where((c) => c.participantes.contains(yo))
        .toList();

    _mensajesSinLeer =
        _conversaciones.fold<int>(0, (s, c) => s + c.noLeidosDe(yo));

    final notifRows = await db.query(
      'notificaciones_internas',
      where: 'usuarioDestino = ?',
      whereArgs: [yo],
      orderBy: 'datetime(fecha) DESC',
      limit: 100,
    );
    _notificaciones = notifRows.map(NotificacionInterna.fromMap).toList();
    _notifSinLeer = _notificaciones.where((n) => !n.leida).length;
    notifyListeners();
  }

  Future<List<Usuario>> usuariosDisponibles() async {
    final yo = _yo;
    final todos = await _usuariosRepo.obtenerTodos();
    return todos.where((u) => u.activo && u.usuario != yo).toList();
  }

  String idDm(String a, String b) {
    final sorted = [a, b]..sort();
    return 'dm_${sorted[0]}_${sorted[1]}';
  }

  Future<ChatConversacion> abrirOCrearDm(Usuario otro) async {
    final yo = AuthService.instance.currentUser!;
    final id = idDm(yo.usuario, otro.usuario);
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'chat_conversaciones',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return ChatConversacion.fromMap(existing.first);
    }

    final participantes = [yo.usuario, otro.usuario]..sort();
    final conv = ChatConversacion(
      id: id,
      tipo: 'dm',
      participantes: participantes,
      nombres: {
        yo.usuario: yo.nombre,
        otro.usuario: otro.nombre,
      },
      creadaAt: DateTime.now(),
    );
    await _upsertConversacionLocal(conv);
    final remote = _chatsCol;
    if (remote != null) {
      try {
        await remote.doc(id).set(conv.toFirestore(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('crear dm remoto: $e');
      }
    }
    await refrescar();
    return conv;
  }

  Future<ChatConversacion> crearGrupo({
    required String titulo,
    required List<Usuario> miembros,
  }) async {
    final yo = AuthService.instance.currentUser!;
    final id = 'grp_${_uuid.v4()}';
    final participantes = {
      yo.usuario,
      ...miembros.map((m) => m.usuario),
    }.toList()
      ..sort();
    final nombres = <String, String>{
      yo.usuario: yo.nombre,
      for (final m in miembros) m.usuario: m.nombre,
    };
    final conv = ChatConversacion(
      id: id,
      tipo: 'grupo',
      participantes: participantes,
      nombres: nombres,
      titulo: titulo.trim().isEmpty ? 'Grupo' : titulo.trim(),
      creadaAt: DateTime.now(),
    );
    await _upsertConversacionLocal(conv);
    final remote = _chatsCol;
    if (remote != null) {
      try {
        await remote.doc(id).set(conv.toFirestore());
      } catch (e) {
        debugPrint('crear grupo remoto: $e');
      }
    }
    await refrescar();
    return conv;
  }

  Future<List<ChatMensaje>> mensajesDe(String conversacionId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'chat_mensajes',
      where: 'conversacionId = ?',
      whereArgs: [conversacionId],
      orderBy: 'datetime(fecha) ASC',
    );
    return rows.map(ChatMensaje.fromMap).toList();
  }

  Stream<List<ChatMensaje>> watchMensajes(String conversacionId) {
    final remote = _chatsCol;
    if (remote != null) {
      return remote
          .doc(conversacionId)
          .collection('mensajes')
          .orderBy('fecha')
          .snapshots()
          .asyncMap((snap) async {
        final list = snap.docs
            .map((d) => ChatMensaje.fromFirestore(
                  {...d.data(), 'conversacionId': conversacionId},
                  id: d.id,
                ))
            .toList();
        final db = await DatabaseHelper.instance.database;
        for (final m in list) {
          await db.insert(
            'chat_mensajes',
            m.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return list;
      });
    }
    return Stream.periodic(const Duration(milliseconds: 1500))
        .asyncMap((_) => mensajesDe(conversacionId));
  }

  Future<ChatMensaje> enviarTexto(String conversacionId, String texto) {
    return _enviar(
      conversacionId: conversacionId,
      tipo: ChatMensajeTipo.texto,
      texto: texto.trim(),
    );
  }

  Future<ChatMensaje> enviarCompartido({
    required String conversacionId,
    required ChatCompartido compartido,
    String? comentario,
  }) {
    return _enviar(
      conversacionId: conversacionId,
      tipo: ChatMensajeTipo.compartido,
      texto: comentario?.trim() ?? '',
      compartido: compartido,
    );
  }

  Future<ChatMensaje> enviarArchivo({
    required String conversacionId,
    required File archivo,
    required String mime,
    String? caption,
  }) async {
    final nombre = p.basename(archivo.path);
    final esImagen = mime.startsWith('image/');

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'comunicaciones', conversacionId));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File(p.join(dir.path, '${_uuid.v4()}_$nombre'));
    await archivo.copy(dest.path);
    var pathGuardado = dest.path;

    // Con Firebase activo, la foto DEBE subir a Storage. Si queda solo el
    // path local, el otro celular/PC ve el mensaje pero no puede abrirla.
    if (_firebaseOk) {
      final tenant = BackendConfigService.instance.tenantId;
      final url = await MediaSyncService.instance.subirArchivo(
        storagePath:
            'tenants/$tenant/chats/$conversacionId/${p.basename(dest.path)}',
        file: dest,
        contentType: mime,
      );
      if (url == null || url.isEmpty) {
        throw StateError(
          'No se pudo subir el archivo a la nube. '
          'Sin eso el otro dispositivo no puede verlo. Reintentá '
          '(revisá conexión y que Storage esté habilitado en Firebase).',
        );
      }
      pathGuardado = url;
    }

    return _enviar(
      conversacionId: conversacionId,
      tipo: esImagen ? ChatMensajeTipo.imagen : ChatMensajeTipo.archivo,
      texto: caption?.trim() ?? '',
      archivoPath: pathGuardado,
      archivoNombre: nombre,
      archivoMime: mime,
    );
  }

  Future<ChatMensaje> _enviar({
    required String conversacionId,
    required String tipo,
    String texto = '',
    String? archivoPath,
    String? archivoNombre,
    String? archivoMime,
    ChatCompartido? compartido,
  }) async {
    final yo = AuthService.instance.currentUser!;
    final id = _uuid.v4();
    final ahora = DateTime.now();
    final db = await DatabaseHelper.instance.database;

    final convRows = await db.query(
      'chat_conversaciones',
      where: 'id = ?',
      whereArgs: [conversacionId],
      limit: 1,
    );
    if (convRows.isEmpty) {
      throw StateError('Conversación no encontrada');
    }
    final conv = ChatConversacion.fromMap(convRows.first);

    final preview = switch (tipo) {
      ChatMensajeTipo.imagen => '📷 Imagen',
      ChatMensajeTipo.archivo => '📎 ${archivoNombre ?? 'Archivo'}',
      ChatMensajeTipo.compartido =>
        '🔗 ${compartido?.titulo ?? 'Elemento compartido'}',
      _ => texto,
    };

    final estados = <String, String>{
      for (final u in conv.participantes)
        u: u == yo.usuario
            ? ChatMensajeEstado.enviado
            : ChatMensajeEstado.entregado,
    };

    final mensaje = ChatMensaje(
      id: id,
      conversacionId: conversacionId,
      autorUsuario: yo.usuario,
      autorNombre: yo.nombre,
      tipo: tipo,
      texto: texto,
      archivoPath: archivoPath,
      archivoNombre: archivoNombre,
      archivoMime: archivoMime,
      compartido: compartido,
      fecha: ahora,
      estados: estados,
    );

    await db.insert(
      'chat_mensajes',
      mensaje.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final noLeidos = Map<String, int>.from(conv.noLeidos);
    for (final u in conv.participantes) {
      if (u == yo.usuario) {
        noLeidos[u] = 0;
      } else {
        noLeidos[u] = (noLeidos[u] ?? 0) + 1;
      }
    }

    final convActualizada = ChatConversacion(
      id: conv.id,
      tipo: conv.tipo,
      participantes: conv.participantes,
      nombres: conv.nombres,
      titulo: conv.titulo,
      ultimoMensaje: preview,
      ultimoMensajeAt: ahora,
      noLeidos: noLeidos,
      creadaAt: conv.creadaAt,
    );
    await _upsertConversacionLocal(convActualizada);

    final remote = _chatsCol;
    if (remote != null) {
      try {
        await remote.doc(conversacionId).set(
              convActualizada.toFirestore(),
              SetOptions(merge: true),
            );
        await remote
            .doc(conversacionId)
            .collection('mensajes')
            .doc(id)
            .set(mensaje.toFirestore());
      } catch (e) {
        debugPrint('enviar remoto: $e');
      }
    }

    for (final u in conv.participantes.where((p) => p != yo.usuario)) {
      await crearNotificacion(
        usuarioDestino: u,
        tipo: tipo == ChatMensajeTipo.archivo || tipo == ChatMensajeTipo.imagen
            ? 'archivo'
            : 'mensaje',
        titulo: conv.tipo == 'grupo' ? (conv.titulo ?? 'Grupo') : yo.nombre,
        cuerpo: preview,
        conversacionId: conversacionId,
      );
    }

    await AuthService.instance.registrarCambio(
      'CHAT_MENSAJE',
      'comunicaciones',
      'Mensaje $tipo en $conversacionId',
      valorNuevo: preview,
    );

    await refrescar();
    return mensaje;
  }

  Future<void> marcarLeidos(String conversacionId) async {
    final yo = _yo;
    if (yo == null) return;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'chat_conversaciones',
      where: 'id = ?',
      whereArgs: [conversacionId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final conv = ChatConversacion.fromMap(rows.first);
    final noLeidos = Map<String, int>.from(conv.noLeidos)..[yo] = 0;
    final actualizada = ChatConversacion(
      id: conv.id,
      tipo: conv.tipo,
      participantes: conv.participantes,
      nombres: conv.nombres,
      titulo: conv.titulo,
      ultimoMensaje: conv.ultimoMensaje,
      ultimoMensajeAt: conv.ultimoMensajeAt,
      noLeidos: noLeidos,
      creadaAt: conv.creadaAt,
    );
    await _upsertConversacionLocal(actualizada);

    final msgs = await mensajesDe(conversacionId);
    for (final m in msgs) {
      if (m.autorUsuario == yo) continue;
      final estados = Map<String, String>.from(m.estados);
      estados[yo] = ChatMensajeEstado.leido;
      final actualizado = ChatMensaje(
        id: m.id,
        conversacionId: m.conversacionId,
        autorUsuario: m.autorUsuario,
        autorNombre: m.autorNombre,
        tipo: m.tipo,
        texto: m.texto,
        archivoPath: m.archivoPath,
        archivoNombre: m.archivoNombre,
        archivoMime: m.archivoMime,
        compartido: m.compartido,
        fecha: m.fecha,
        estados: estados,
      );
      await db.insert(
        'chat_mensajes',
        actualizado.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final remote = _chatsCol;
    if (remote != null) {
      try {
        await remote.doc(conversacionId).update({'noLeidos.$yo': 0});
      } catch (e) {
        debugPrint('marcar leidos remoto: $e');
      }
    }
    await refrescar();
  }

  Future<void> crearNotificacion({
    required String usuarioDestino,
    required String tipo,
    required String titulo,
    required String cuerpo,
    String? conversacionId,
    String? entidadTipo,
    String? entidadId,
  }) async {
    final id = _uuid.v4();
    final n = NotificacionInterna(
      id: id,
      usuarioDestino: usuarioDestino,
      tipo: tipo,
      titulo: titulo,
      cuerpo: cuerpo,
      conversacionId: conversacionId,
      entidadTipo: entidadTipo,
      entidadId: entidadId,
      fecha: DateTime.now(),
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'notificaciones_internas',
      n.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final remote = _notifCol;
    if (remote != null) {
      try {
        await remote.doc(id).set(n.toFirestore());
      } catch (e) {
        debugPrint('notif remota: $e');
      }
    }
    if (usuarioDestino == _yo) {
      await refrescar();
    }
  }

  Future<void> marcarNotificacionLeida(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'notificaciones_internas',
      {'leida': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    final remote = _notifCol;
    if (remote != null) {
      try {
        await remote.doc(id).set({'leida': true}, SetOptions(merge: true));
      } catch (_) {}
    }
    await refrescar();
  }

  Future<void> marcarTodasNotificacionesLeidas() async {
    final yo = _yo;
    if (yo == null) return;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'notificaciones_internas',
      {'leida': 1},
      where: 'usuarioDestino = ? AND leida = 0',
      whereArgs: [yo],
    );
    await refrescar();
  }

  Future<List<ChatMensaje>> buscarMensajes({
    String? texto,
    String? autor,
    String? tipo,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (texto != null && texto.trim().isNotEmpty) {
      where.add('(texto LIKE ? OR archivoNombre LIKE ?)');
      final like = '%${texto.trim()}%';
      args.addAll([like, like]);
    }
    if (autor != null && autor.isNotEmpty) {
      where.add('autorUsuario = ?');
      args.add(autor);
    }
    if (tipo != null && tipo.isNotEmpty) {
      where.add('tipo = ?');
      args.add(tipo);
    }
    final rows = await db.query(
      'chat_mensajes',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'datetime(fecha) DESC',
      limit: 50,
    );
    return rows.map(ChatMensaje.fromMap).toList();
  }

  Future<void> _upsertConversacionLocal(ChatConversacion c) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'chat_conversaciones',
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
