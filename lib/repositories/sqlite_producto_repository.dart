import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/producto.dart';
import 'producto_repository.dart';

class SqliteProductoRepository implements ProductoRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  @override
  Future<int> insertar(Producto producto) async {
    final db = await _databaseHelper.database;
    return db.insert(
      'productos',
      producto.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    final db = await _databaseHelper.database;
    final batch = db.batch();
    for (final producto in productos) {
      batch.insert(
        'productos',
        producto.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Producto>> obtenerTodos({int? limit, int? offset}) async {
    final db = await _databaseHelper.database;
    final resultado = await db.query(
      'productos',
      orderBy: 'descripcion',
      limit: limit,
      offset: offset,
    );
    return resultado.map(Producto.fromMap).toList();
  }

  @override
  Future<Producto?> buscarPorCodigo(String codigo) async {
    final db = await _databaseHelper.database;
    final resultado = await db.query(
      'productos',
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return Producto.fromMap(resultado.first);
  }

  @override
  Future<Producto?> buscarPorCodigoBarras(String codigoBarras) async {
    if (codigoBarras.trim().isEmpty) return null;
    final db = await _databaseHelper.database;
    final resultado = await db.query(
      'productos',
      where: 'codigo_barras = ? OR codigo = ?',
      whereArgs: [codigoBarras, codigoBarras],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return Producto.fromMap(resultado.first);
  }

  @override
  Future<bool> tieneProductos() async {
    final db = await _databaseHelper.database;
    final resultado = await db.rawQuery('SELECT COUNT(*) total FROM productos');
    return Sqflite.firstIntValue(resultado)! > 0;
  }

  @override
  Future<int> actualizar(Producto producto) async {
    final db = await _databaseHelper.database;
    return db.update(
      'productos',
      producto.toMap(),
      where: 'id = ?',
      whereArgs: [producto.id],
    );
  }

  @override
  Future<int> eliminar(int id) async {
    final db = await _databaseHelper.database;
    return db.delete(
      'productos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) async* {
    yield await obtenerTodos(limit: limit);
  }
}
