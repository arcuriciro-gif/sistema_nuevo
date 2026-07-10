import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../config/backend_config_service.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../../database/database_helper.dart';
import '../../models/producto.dart';
import '../../models/venta.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ventasSub;
  bool _sincronizando = false;
  bool _sincronizandoVentas = false;

  CollectionReference<Map<String, dynamic>> get _ventasCol {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('ventas');
  }

  Future<void> start() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    await _productosSub?.cancel();
    await _ventasSub?.cancel();
    _productosSub = _remote.watchTodos(limit: 1000).listen(
      _aplicarProductosRemotos,
      onError: (Object error) => debugPrint('Sync productos: $error'),
    );
    _ventasSub = _ventasCol.snapshots().listen(
      _aplicarVentasRemotas,
      onError: (Object error) => debugPrint('Sync ventas: $error'),
    );
  }

  Future<void> stop() async {
    await _productosSub?.cancel();
    await _ventasSub?.cancel();
    _productosSub = null;
    _ventasSub = null;
  }

  ProductoRepository get writeRepository {
    final authOk = FirebaseAuthUsuarioService.instance.uidActual != null;
    if (BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady &&
        authOk) {
      return _DualProductoRepository(local: _cache, remote: _remote);
    }
    return _cache;
  }

  bool get _puedeEscribirRemoto {
    return BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady &&
        FirebaseAuthUsuarioService.instance.uidActual != null;
  }

  Future<void> subirVenta(int ventaId) async {
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT v.*, c.nombre AS clienteNombre
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.id = ?
      ''', [ventaId]);
      if (rows.isEmpty) return;
      final venta = Venta.fromMap(rows.first);
      final items = await db.query(
        'ventas_items',
        where: 'ventaId = ?',
        whereArgs: [ventaId],
      );
      final pagos = await db.query(
        'pagos',
        where: 'ventaId = ?',
        whereArgs: [ventaId],
      );
      final docId = venta.numero.isNotEmpty ? venta.numero : 'v_$ventaId';
      await _ventasCol.doc(docId).set({
        ...venta.toFirestore(),
        'localId': ventaId,
        'items': items,
        'pagos': pagos,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore subir venta: $e');
    }
  }

  Future<void> eliminarVentaRemota(Venta venta) async {
    if (!_puedeEscribirRemoto) return;
    try {
      final docId = venta.numero.isNotEmpty ? venta.numero : 'v_${venta.id}';
      await _ventasCol.doc(docId).delete();
    } catch (e) {
      debugPrint('Firestore eliminar venta: $e');
    }
  }

  Future<void> _aplicarVentasRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoVentas) return;
    _sincronizandoVentas = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        final existentes = await db.query(
          'ventas',
          where: 'numero = ?',
          whereArgs: [numero],
          limit: 1,
        );
        final map = Map<String, dynamic>.from(data)
          ..remove('items')
          ..remove('pagos')
          ..remove('localId')
          ..remove('clienteNombre')
          ..remove('actualizadoEn')
          ..remove('id');
        int ventaId;
        if (existentes.isEmpty) {
          ventaId = await db.insert('ventas', map);
        } else {
          ventaId = existentes.first['id'] as int;
          await db.update(
            'ventas',
            map,
            where: 'id = ?',
            whereArgs: [ventaId],
          );
          await db.delete(
            'ventas_items',
            where: 'ventaId = ?',
            whereArgs: [ventaId],
          );
          await db.delete('pagos', where: 'ventaId = ?', whereArgs: [ventaId]);
        }
        final items = (data['items'] as List?) ?? const [];
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          item.remove('id');
          item['ventaId'] = ventaId;
          await db.insert('ventas_items', item);
        }
        final pagos = (data['pagos'] as List?) ?? const [];
        for (final raw in pagos) {
          final pago = Map<String, dynamic>.from(raw as Map);
          pago.remove('id');
          pago['ventaId'] = ventaId;
          await db.insert('pagos', pago);
        }
      }
      DataRefreshHub.instance.notifyVentas();
    } catch (e) {
      debugPrint('Aplicar ventas remotas: $e');
    } finally {
      _sincronizandoVentas = false;
    }
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
  Future<Producto?> buscarPorCodigo(String codigo) =>
      local.buscarPorCodigo(codigo);

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
    final rows =
        await db.query('productos', where: 'id = ?', whereArgs: [id], limit: 1);
    final result = await local.eliminar(id);
    if (rows.isNotEmpty) {
      final producto = Producto.fromMap(rows.first).copyWith(
        deletedAt: DateTime.now().toIso8601String(),
        favorito: false,
      );
      try {
        await remote.actualizar(producto);
      } catch (error) {
        debugPrint('Firestore soft-delete producto: $error');
      }
    }
    return result;
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) =>
      remote.watchTodos(limit: limit);
}
