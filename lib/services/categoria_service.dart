import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../database/database_helper.dart';
import '../models/categoria.dart';

class CategoriaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> _syncNube() async {
    try {
      await FirestoreSyncService.instance.subirCategorias();
      DataRefreshHub.instance.notifyTodo();
    } catch (_) {}
  }

  Future<List<Categoria>> obtenerTodas({bool soloActivas = false}) async {
    final db = await _db.database;
    final rows = await db.query(
      'categorias',
      where: soloActivas ? 'activa = 1' : null,
      orderBy: 'nombre ASC',
    );
    return rows.map(Categoria.fromMap).toList();
  }

  Future<Categoria?> obtenerPorId(int id) async {
    final db = await _db.database;
    final rows = await db.query('categorias', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Categoria.fromMap(rows.first);
  }

  Future<int> crear(Categoria categoria) async {
    final db = await _db.database;
    final map = categoria.toMap()..remove('id');
    final id = await db.insert('categorias', map);
    await _syncNube();
    return id;
  }

  Future<int> actualizar(Categoria categoria) async {
    final db = await _db.database;
    final n = await db.update(
      'categorias',
      categoria.toMap(),
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
    await _syncNube();
    return n;
  }

  Future<int> eliminar(int id) async {
    final db = await _db.database;
    final n = await db.delete('categorias', where: 'id = ?', whereArgs: [id]);
    await _syncNube();
    return n;
  }

  Future<List<String>> obtenerNombres() async {
    final categorias = await obtenerTodas(soloActivas: true);
    return categorias.map((c) => c.nombre).toList();
  }
}
