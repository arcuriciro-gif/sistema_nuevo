import '../database/database_helper.dart';
import '../models/comentario_interno.dart';
import 'auth_service.dart';

class ComentarioInternoService {
  ComentarioInternoService._();
  static final ComentarioInternoService instance = ComentarioInternoService._();

  Future<List<ComentarioInterno>> listar({
    required String entidadTipo,
    required String entidadId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'comentarios_internos',
      where: 'entidadTipo = ? AND entidadId = ? AND activo = 1',
      whereArgs: [entidadTipo, entidadId],
      orderBy: 'datetime(fecha) ASC',
    );
    return rows.map(ComentarioInterno.fromMap).toList();
  }

  Future<int> contar({
    required String entidadTipo,
    required String entidadId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM comentarios_internos
      WHERE entidadTipo = ? AND entidadId = ? AND activo = 1
      ''',
      [entidadTipo, entidadId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<ComentarioInterno> agregar({
    required String entidadTipo,
    required String entidadId,
    required String texto,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      throw StateError('Debés iniciar sesión para comentar');
    }
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      throw ArgumentError('El comentario no puede estar vacío');
    }

    final comentario = ComentarioInterno(
      entidadTipo: entidadTipo,
      entidadId: entidadId,
      usuario: user.usuario,
      nombre: user.nombre,
      texto: limpio,
      fecha: DateTime.now(),
    );

    final db = await DatabaseHelper.instance.database;
    final id = await db.insert(
      'comentarios_internos',
      comentario.toMap()..remove('id'),
    );

    await AuthService.instance.registrarCambio(
      'COMENTARIO_INTERNO',
      entidadTipo,
      'Comentario en $entidadTipo #$entidadId',
      valorNuevo: limpio,
    );

    return ComentarioInterno(
      id: id,
      entidadTipo: comentario.entidadTipo,
      entidadId: comentario.entidadId,
      usuario: comentario.usuario,
      nombre: comentario.nombre,
      texto: comentario.texto,
      fecha: comentario.fecha,
    );
  }

  Future<void> eliminar(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'comentarios_internos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final c = ComentarioInterno.fromMap(rows.first);
    final yo = AuthService.instance.currentUser;
    final esAdmin = AuthService.instance.esAdministrador();
    if (yo == null) return;
    if (!esAdmin && c.usuario != yo.usuario) {
      throw StateError('Solo podés borrar tus propios comentarios');
    }
    await db.update(
      'comentarios_internos',
      {'activo': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuthService.instance.registrarCambio(
      'BORRAR_COMENTARIO_INTERNO',
      c.entidadTipo,
      'Comentario eliminado en ${c.entidadTipo} #${c.entidadId}',
      valorAnterior: c.texto,
    );
  }
}
