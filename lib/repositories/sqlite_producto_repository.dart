import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/producto.dart';
import 'producto_repository.dart';

class SqliteProductoRepository implements ProductoRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  static const String _activosWhere =
      "(deleted_at IS NULL OR deleted_at = '')";

  @override
  Future<int> insertar(Producto producto) async {
    final db = await _databaseHelper.database;
    final map = producto.toMap()..remove('id');
    map['deleted_at'] = null;
    return db.insert(
      'productos',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    final db = await _databaseHelper.database;
    final batch = db.batch();
    for (final producto in productos) {
      final map = producto.toMap()..remove('id');
      map['deleted_at'] = null;
      batch.insert(
        'productos',
        map,
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
      where: _activosWhere,
      orderBy: 'favorito DESC, descripcion',
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
      where: 'codigo = ? AND $_activosWhere',
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
      where: '(codigo_barras = ? OR codigo = ?) AND $_activosWhere',
      whereArgs: [codigoBarras, codigoBarras],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return Producto.fromMap(resultado.first);
  }

  @override
  Future<bool> tieneProductos() async {
    final db = await _databaseHelper.database;
    final resultado = await db.rawQuery(
      'SELECT COUNT(*) total FROM productos WHERE $_activosWhere',
    );
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

  /// Soft-delete: marca deleted_at en lugar de borrar la fila.
  @override
  Future<int> eliminar(int id) async {
    final db = await _databaseHelper.database;
    return db.update(
      'productos',
      {'deleted_at': DateTime.now().toIso8601String(), 'favorito': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) async* {
    yield await obtenerTodos(limit: limit);
  }
}
