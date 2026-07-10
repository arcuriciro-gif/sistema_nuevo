import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../config/backend_config_service.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_bootstrap.dart';
import '../../database/database_helper.dart';
import '../../models/producto.dart';
import '../../repositories/firestore_producto_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/sqlite_producto_repository.dart';

/// Mantiene SQLite sincronizado con Firestore en tiempo real.
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirestoreSyncService instance = FirestoreSyncService._();

  final SqliteProductoRepository _cache = SqliteProductoRepository();
  final FirestoreProductoRepository _remote = FirestoreProductoRepository();

  StreamSubscription<List<Producto>>? _productosSub;
  bool _sincronizando = false;

  Future<void> start() async {
    if (!BackendConfigService.instance.firebaseEnabled || !FirebaseBootstrap.isReady) {
      return;
    }
    await _productosSub?.cancel();
    _productosSub = _remote.watchTodos(limit: 1000).listen(
      _aplicarProductosRemotos,
      onError: (Object error) => debugPrint('Sync productos: $error'),
    );
  }

  Future<void> stop() async {
    await _productosSub?.cancel();
    _productosSub = null;
  }

  ProductoRepository get writeRepository {
    if (BackendConfigService.instance.firebaseEnabled && FirebaseBootstrap.isReady) {
      return _DualProductoRepository(local: _cache, remote: _remote);
    }
    return _cache;
  }

  Future<void> _aplicarProductosRemotos(List<Producto> remotos) async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final batch = db.batch();
      for (final producto in remotos) {
        final local = await _cache.buscarPorCodigo(producto.codigo);
        final merged = producto.copyWith(id: local?.id);
        final data = merged.toMap();
        if (local?.id != null) {
          batch.update(
            'productos',
            data..remove('id'),
            where: 'id = ?',
            whereArgs: [local!.id],
          );
        } else {
          batch.insert(
            'productos',
            data..remove('id'),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
      DataRefreshHub.instance.notifyProductos();
    } finally {
      _sincronizando = false;
    }
  }
}

class _DualProductoRepository implements ProductoRepository {
  _DualProductoRepository({required this.local, required this.remote});

  final SqliteProductoRepository local;
  final FirestoreProductoRepository remote;

  @override
  Future<int> insertar(Producto producto) async {
    final id = await local.insertar(producto);
    final conId = producto.copyWith(id: id);
    try {
      await remote.insertar(conId);
    } catch (error) {
      debugPrint('Firestore insertar producto: $error');
    }
    return id;
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    await local.insertarLista(productos);
    try {
      await remote.insertarLista(productos);
    } catch (error) {
      debugPrint('Firestore insertarLista productos: $error');
    }
  }

  @override
  Future<List<Producto>> obtenerTodos({int? limit, int? offset}) =>
      local.obtenerTodos(limit: limit, offset: offset);

  @override
  Future<Producto?> buscarPorCodigo(String codigo) => local.buscarPorCodigo(codigo);

  @override
  Future<Producto?> buscarPorCodigoBarras(String codigoBarras) =>
      local.buscarPorCodigoBarras(codigoBarras);

  @override
  Future<bool> tieneProductos() => local.tieneProductos();

  @override
  Future<int> actualizar(Producto producto) async {
    final result = await local.actualizar(producto);
    try {
      await remote.actualizar(producto);
    } catch (error) {
      debugPrint('Firestore actualizar producto: $error');
    }
    return result;
  }

  @override
  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('productos', where: 'id = ?', whereArgs: [id], limit: 1);
    final result = await local.eliminar(id);
    if (rows.isNotEmpty) {
      final producto = Producto.fromMap(rows.first);
      if (producto.codigo.isNotEmpty) {
        try {
          await remote.eliminarPorCodigo(producto.codigo);
        } catch (error) {
          debugPrint('Firestore eliminar producto: $error');
        }
      }
    }
    return result;
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) =>
      remote.watchTodos(limit: limit);
}
