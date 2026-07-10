import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/usuario.dart';
import 'usuario_repository.dart';

class SqliteUsuarioRepository implements UsuarioRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  @override
  Future<List<Usuario>> obtenerTodos() async {
    final db = await _dbHelper.database;
    final rows = await db.query('usuarios', orderBy: 'activo DESC, nombre ASC');
    return rows.map(Usuario.fromMap).toList();
  }

  @override
  Future<Usuario?> buscarPorUsuario(String usuario) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'usuarios',
      where: 'LOWER(usuario) = ?',
      whereArgs: [usuario.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  Future<Usuario?> buscarPorEmail(String email) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'usuarios',
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  /// Inserta o actualiza por firebase_uid / usuario (para login en otra PC).
  Future<Usuario> upsertDesdeRemoto(Usuario usuario) async {
    final db = await _dbHelper.database;
    Usuario? existente;
    final uid = usuario.firebaseUid;
    if (uid != null && uid.isNotEmpty) {
      existente = await buscarPorFirebaseUid(uid);
    }
    existente ??= await buscarPorUsuario(usuario.usuario);
    if (existente == null && usuario.email.trim().isNotEmpty) {
      existente = await buscarPorEmail(usuario.email);
    }

    if (existente == null) {
      final id = await db.insert(
        'usuarios',
        usuario.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return usuario.copyWith(id: id);
    }

    final merged = existente.copyWith(
      firebaseUid: usuario.firebaseUid ?? existente.firebaseUid,
      nombre: usuario.nombre.isNotEmpty ? usuario.nombre : existente.nombre,
      usuario: usuario.usuario.isNotEmpty ? usuario.usuario : existente.usuario,
      password: usuario.password.isNotEmpty ? usuario.password : existente.password,
      rol: usuario.rol,
      activo: usuario.activo,
      debeCambiarPassword: usuario.debeCambiarPassword,
      email: usuario.email.isNotEmpty ? usuario.email : existente.email,
      foto: usuario.foto.isNotEmpty ? usuario.foto : existente.foto,
      fechaCreacion: existente.fechaCreacion ?? usuario.fechaCreacion,
      ultimoAcceso: usuario.ultimoAcceso ?? existente.ultimoAcceso,
    );
    await actualizar(merged);
    return merged;
  }

  @override
  Future<Usuario?> buscarPorFirebaseUid(String uid) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'usuarios',
      where: 'firebase_uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Usuario.fromMap(rows.first);
  }

  @override
  Future<int> insertar(Usuario usuario) async {
    final db = await _dbHelper.database;
    return db.insert(
      'usuarios',
      usuario.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<int> actualizar(Usuario usuario) async {
    final db = await _dbHelper.database;
    return db.update(
      'usuarios',
      usuario.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [usuario.id],
    );
  }

  @override
  Future<int> desactivar(int id) async {
    final db = await _dbHelper.database;
    return db.update(
      'usuarios',
      {'activo': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<bool> existeUsuario(String usuario) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'usuarios',
      columns: ['id'],
      where: 'LOWER(usuario) = ?',
      whereArgs: [usuario.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Stream<List<Usuario>> watchTodos() async* {
    yield await obtenerTodos();
  }
}
