import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/categoria.dart';

class CategoriaService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Local primero; sync en segundo plano (misma política que listas/precios).
  void _syncNube() {
    DataRefreshHub.instance.notifyTodo();
    syncInBackground(
      FirestoreSyncService.instance.subirCategorias(),
      tag: 'subirCategorias',
    );
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
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.crear,
      operacion: 'crear categoría',
    );
    final db = await _db.database;
    final map = categoria.toMap()..remove('id');
    final id = await db.insert('categorias', map);
    _syncNube();
    return id;
  }

  Future<int> actualizar(Categoria categoria) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.editar,
      operacion: 'editar categoría',
    );
    final db = await _db.database;
    final n = await db.update(
      'categorias',
      categoria.toMap(),
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
    _syncNube();
    return n;
  }

  Future<int> eliminar(int id) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.eliminar,
      operacion: 'eliminar categoría',
    );
    final db = await _db.database;
    final n = await db.delete('categorias', where: 'id = ?', whereArgs: [id]);
    _syncNube();
    return n;
  }

  Future<List<String>> obtenerNombres() async {
    final categorias = await obtenerTodas(soloActivas: true);
    return categorias.map((c) => c.nombre).toList();
  }
}
