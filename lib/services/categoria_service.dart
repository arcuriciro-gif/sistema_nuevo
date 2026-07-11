import 'dart:convert';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
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
    final id = await db.insert('categorias', map);
    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'categoria',
      id: id,
      upload: () => FirestoreSyncService.instance.subirCategoria(id),
    );
    DataRefreshHub.instance.notifyTodo();
    return id;
  }

  Future<int> actualizar(Categoria categoria) async {
    final db = await _db.database;
    final result = await db.update(
      'categorias',
      categoria.toMap(),
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
    if (categoria.id != null) {
      await SyncQueueService.instance.pushOrEnqueueUpsert(
        entityType: 'categoria',
        id: categoria.id!,
        upload: () =>
            FirestoreSyncService.instance.subirCategoria(categoria.id!),
      );
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
  }

  Future<int> eliminar(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'categorias',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final nombre = rows.isNotEmpty ? rows.first['nombre']?.toString() ?? '' : '';
    final result = await db.delete('categorias', where: 'id = ?', whereArgs: [id]);
    if (nombre.isNotEmpty) {
      await SyncQueueService.instance.pushOrEnqueue(
        entityType: 'categoria',
        entityId: nombre,
        operation: 'delete',
        payloadJson: jsonEncode({'nombre': nombre}),
        upload: () =>
            FirestoreSyncService.instance.eliminarCategoriaRemota(nombre),
      );
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
  }

  Future<List<String>> obtenerNombres() async {
    final categorias = await obtenerTodas(soloActivas: true);
    return categorias.map((c) => c.nombre).toList();
  }
}
