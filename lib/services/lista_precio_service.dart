import 'dart:convert';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../database/database_helper.dart';
import '../models/lista_precio.dart';

class ListaPrecioService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> insertar(ListaPrecio lista) async {
    final db = await dbHelper.database;
    final id = await db.insert('listas_precios', lista.toMap()..remove('id'));
    await SyncQueueService.instance.pushOrEnqueueUpsert(
      entityType: 'lista_precio',
      id: id,
      upload: () => FirestoreSyncService.instance.subirListaPrecio(id),
    );
    DataRefreshHub.instance.notifyTodo();
    return id;
  }

  Future<int> actualizar(ListaPrecio lista) async {
    final db = await dbHelper.database;
    final result = await db.update(
      'listas_precios',
      lista.toMap(),
      where: 'id = ?',
      whereArgs: [lista.id],
    );
    if (lista.id != null) {
      await SyncQueueService.instance.pushOrEnqueueUpsert(
        entityType: 'lista_precio',
        id: lista.id!,
        upload: () =>
            FirestoreSyncService.instance.subirListaPrecio(lista.id!),
      );
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
  }

  Future<int> eliminar(int id) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'listas_precios',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final nombre = rows.isNotEmpty ? rows.first['nombre']?.toString() ?? '' : '';
    final result = await db.delete(
      'listas_precios',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (nombre.isNotEmpty) {
      await SyncQueueService.instance.pushOrEnqueue(
        entityType: 'lista_precio',
        entityId: nombre,
        operation: 'delete',
        payloadJson: jsonEncode({'nombre': nombre}),
        upload: () =>
            FirestoreSyncService.instance.eliminarListaPrecioRemota(nombre),
      );
    }
    DataRefreshHub.instance.notifyTodo();
    return result;
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
