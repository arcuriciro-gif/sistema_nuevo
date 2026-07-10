import '../database/database_helper.dart';
import '../models/categoria.dart';

class CategoriaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

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
    return db.insert('categorias', map);
  }

  Future<int> actualizar(Categoria categoria) async {
    final db = await _db.database;
    return db.update(
      'categorias',
      categoria.toMap(),
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await _db.database;
    return db.delete('categorias', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> obtenerNombres() async {
    final categorias = await obtenerTodas(soloActivas: true);
    return categorias.map((c) => c.nombre).toList();
  }
}
