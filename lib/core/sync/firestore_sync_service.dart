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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remitosSub;
  bool _sincronizando = false;
  bool _sincronizandoVentas = false;
  bool _sincronizandoRemitos = false;

  CollectionReference<Map<String, dynamic>> get _ventasCol {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('ventas');
  }

  CollectionReference<Map<String, dynamic>> get _remitosCol {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('remitos');
  }

  Future<void> start() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    await _productosSub?.cancel();
    await _ventasSub?.cancel();
    await _remitosSub?.cancel();
    _productosSub = _remote.watchTodos(limit: 1000).listen(
      _aplicarProductosRemotos,
      onError: (Object error) => debugPrint('Sync productos: $error'),
    );
    _ventasSub = _ventasCol.snapshots().listen(
      _aplicarVentasRemotas,
      onError: (Object error) => debugPrint('Sync ventas: $error'),
    );
    _remitosSub = _remitosCol.snapshots().listen(
      _aplicarRemitosRemotos,
      onError: (Object error) => debugPrint('Sync remitos: $error'),
    );
  }

  Future<void> stop() async {
    await _productosSub?.cancel();
    await _ventasSub?.cancel();
    await _remitosSub?.cancel();
    _productosSub = null;
    _ventasSub = null;
    _remitosSub = null;
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
      final itemsEnriquecidos = <Map<String, dynamic>>[];
      for (final item in items) {
        final map = Map<String, dynamic>.from(item);
        final pid = item['productoId'];
        if (pid != null) {
          final prod = await db.query(
            'productos',
            columns: ['codigo'],
            where: 'id = ?',
            whereArgs: [pid],
            limit: 1,
          );
          if (prod.isNotEmpty) {
            map['productoCodigo'] = prod.first['codigo'];
          }
        }
        itemsEnriquecidos.add(map);
      }
      final docId = venta.numero.isNotEmpty ? venta.numero : 'v_$ventaId';
      await _ventasCol.doc(docId).set({
        ...venta.toFirestore(),
        'localId': ventaId,
        'clienteNombre': rows.first['clienteNombre'],
        'items': itemsEnriquecidos,
        'pagos': pagos,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
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

  /// Sube remito + ítems y empuja el stock actualizado de cada producto.
  Future<void> subirRemito(int remitoId) async {
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT r.*, c.nombre AS clienteNombre
        FROM remitos r
        LEFT JOIN clientes c ON c.id = r.clienteId
        WHERE r.id = ?
      ''', [remitoId]);
      if (rows.isEmpty) return;
      final remito = rows.first;
      final items = await db.rawQuery('''
        SELECT ri.*, p.codigo AS productoCodigo, p.descripcion AS productoDescripcion
        FROM remito_items ri
        LEFT JOIN productos p ON p.id = ri.productoId
        WHERE ri.remitoId = ?
      ''', [remitoId]);

      final numero = remito['numero']?.toString() ?? 'R_$remitoId';
      await _remitosCol.doc(numero).set({
        'numero': numero,
        'clienteId': remito['clienteId'],
        'clienteNombre': remito['clienteNombre'],
        'fecha': remito['fecha'],
        'total': remito['total'],
        'descuento': remito['descuento'],
        'estado': remito['estado'],
        'estadoPago': remito['estadoPago'],
        'observaciones': remito['observaciones'],
        'fechaCreacion': remito['fechaCreacion'],
        'localId': remitoId,
        'items': items,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      final productoIds =
          items.map((e) => e['productoId']).whereType<int>().toSet();
      for (final pid in productoIds) {
        await subirProductoPorId(pid);
      }
    } catch (e) {
      debugPrint('Firestore subir remito: $e');
    }
  }

  Future<void> subirProductoPorId(int productoId) async {
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [productoId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final producto = Producto.fromMap(rows.first);
      await _remote.actualizar(producto);
    } catch (e) {
      debugPrint('Firestore subir producto $productoId: $e');
    }
  }

  Future<void> _aplicarRemitosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoRemitos) return;
    _sincronizandoRemitos = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        final existentes = await db.query(
          'remitos',
          where: 'numero = ?',
          whereArgs: [numero],
          limit: 1,
        );

        int? clienteId = (data['clienteId'] as num?)?.toInt();
        final clienteNombre = data['clienteNombre']?.toString();
        if (clienteNombre != null && clienteNombre.isNotEmpty) {
          final clientes = await db.query(
            'clientes',
            where: 'nombre = ?',
            whereArgs: [clienteNombre],
            limit: 1,
          );
          if (clientes.isNotEmpty) {
            clienteId = clientes.first['id'] as int?;
          }
        }

        final remitoMap = <String, dynamic>{
          'numero': numero,
          'clienteId': clienteId,
          'fecha': data['fecha'],
          'total': data['total'] ?? 0,
          'descuento': data['descuento'] ?? 0,
          'estado': data['estado'] ?? 'confirmado',
          'estadoPago': data['estadoPago'] ?? 'pendiente',
          'observaciones': data['observaciones'] ?? '',
          'fechaCreacion':
              data['fechaCreacion'] ?? DateTime.now().toIso8601String(),
        };

        final int remitoId;
        if (existentes.isEmpty) {
          remitoId = await db.insert('remitos', remitoMap);
        } else {
          remitoId = existentes.first['id'] as int;
          await db.update(
            'remitos',
            remitoMap,
            where: 'id = ?',
            whereArgs: [remitoId],
          );
          await db.delete(
            'remito_items',
            where: 'remitoId = ?',
            whereArgs: [remitoId],
          );
        }

        final items = (data['items'] as List?) ?? const [];
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          int? productoId = (item['productoId'] as num?)?.toInt();
          final codigo = item['productoCodigo']?.toString();
          if (codigo != null && codigo.isNotEmpty) {
            final prod = await db.query(
              'productos',
              columns: ['id'],
              where: 'codigo = ?',
              whereArgs: [codigo],
              limit: 1,
            );
            if (prod.isNotEmpty) {
              productoId = prod.first['id'] as int?;
            }
          }
          if (productoId == null) continue;

          await db.insert('remito_items', {
            'remitoId': remitoId,
            'productoId': productoId,
            'cantidad': item['cantidad'] ?? 0,
            'precio': item['precio'] ?? item['precioUnitario'] ?? 0,
            'subtotal': item['subtotal'] ?? 0,
            'costoUnitario': item['costoUnitario'] ?? 0,
            'ganancia': item['ganancia'] ?? 0,
          });
        }
        // Stock llega por sync de productos (evita doble descuento).
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar remitos remotos: $e');
    } finally {
      _sincronizandoRemitos = false;
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

        final clienteNombre = data['clienteNombre']?.toString();
        if (clienteNombre != null && clienteNombre.isNotEmpty) {
          final clientes = await db.query(
            'clientes',
            where: 'nombre = ?',
            whereArgs: [clienteNombre],
            limit: 1,
          );
          if (clientes.isNotEmpty) {
            map['clienteId'] = clientes.first['id'];
          }
        }

        final int ventaId;
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
          final codigo = item.remove('productoCodigo')?.toString();
          if (codigo != null && codigo.isNotEmpty) {
            final prod = await db.query(
              'productos',
              columns: ['id'],
              where: 'codigo = ?',
              whereArgs: [codigo],
              limit: 1,
            );
            if (prod.isNotEmpty) {
              item['productoId'] = prod.first['id'];
            }
          }
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
