import '../database/database_helper.dart';
import '../models/lista_precio.dart';

class ListaPrecioService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> insertar(ListaPrecio lista) async {
    final db = await dbHelper.database;
    return db.insert('listas_precios', lista.toMap()..remove('id'));
  }

  Future<int> actualizar(ListaPrecio lista) async {
    final db = await dbHelper.database;
    return db.update(
      'listas_precios',
      lista.toMap(),
      where: 'id = ?',
      whereArgs: [lista.id],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await dbHelper.database;
    return db.delete(
      'listas_precios',
      where: 'id = ?',
      whereArgs: [id],
    );
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
