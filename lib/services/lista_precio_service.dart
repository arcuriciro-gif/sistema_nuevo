import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_background.dart';
import '../database/database_helper.dart';
import '../models/lista_precio.dart';

class ListaPrecioService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  /// Local primero; la nube va en segundo plano (modo avión / corte de red).
  void _syncNube() {
    DataRefreshHub.instance.notifyTodo();
    syncInBackground(
      FirestoreSyncService.instance.subirListasPrecios(),
      tag: 'subirListas',
    );
  }

  Future<int> insertar(ListaPrecio lista) async {
    AuthorizationService.instance.require(
      AuthModules.listasPrecios,
      AuthzAction.crear,
      operacion: 'crear lista de precios',
    );
    final db = await dbHelper.database;
    final id = await db.insert('listas_precios', lista.toMap()..remove('id'));
    _syncNube();
    return id;
  }

  Future<int> actualizar(ListaPrecio lista) async {
    AuthorizationService.instance.require(
      AuthModules.listasPrecios,
      AuthzAction.editar,
      operacion: 'editar lista de precios',
    );
    final db = await dbHelper.database;
    final n = await db.update(
      'listas_precios',
      lista.toMap(),
      where: 'id = ?',
      whereArgs: [lista.id],
    );
    _syncNube();
    return n;
  }

  Future<int> eliminar(int id) async {
    AuthorizationService.instance.require(
      AuthModules.listasPrecios,
      AuthzAction.eliminar,
      operacion: 'eliminar lista de precios',
    );
    final db = await dbHelper.database;
    final n = await db.delete(
      'listas_precios',
      where: 'id = ?',
      whereArgs: [id],
    );
    _syncNube();
    return n;
  }

  Future<List<ListaPrecio>> obtenerTodas() async {
    final db = await dbHelper.database;
    final resultado = await db.query(
      'listas_precios',
      orderBy: 'prioridad DESC, orden ASC, nombre',
    );
    return resultado.map((e) => ListaPrecio.fromMap(e)).toList();
  }

  Future<List<ListaPrecio>> obtenerActivas() async {
    final db = await dbHelper.database;
    final resultado = await db.query(
      'listas_precios',
      where: 'activa = 1',
      orderBy: 'prioridad DESC, orden ASC, nombre',
    );
    return resultado.map((e) => ListaPrecio.fromMap(e)).toList();
  }
}
