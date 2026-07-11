import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../../services/cuenta_corriente_service.dart';
import '../../database/database_helper.dart';
import '../../models/cliente.dart';
import '../../models/comentario_interno.dart';
import '../../models/documento_cliente.dart';
import '../../models/producto.dart';
import '../../models/proveedor.dart';
import '../../models/venta.dart';
import '../../repositories/firestore_producto_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/sqlite_producto_repository.dart';
import 'media_sync_service.dart';
import 'sync_queue_service.dart';

/// Mantiene SQLite sincronizado con Firestore en tiempo real.
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirestoreSyncService instance = FirestoreSyncService._();

  final SqliteProductoRepository _cache = SqliteProductoRepository();
  final FirestoreProductoRepository _remote = FirestoreProductoRepository();

  StreamSubscription<List<Producto>>? _productosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ventasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remitosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clientesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _proveedoresSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _comprasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pedidosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _documentosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _comentariosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _categoriasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listasPreciosSub;

  bool _sincronizando = false;
  bool _sincronizandoVentas = false;
  bool _sincronizandoRemitos = false;
  bool _sincronizandoClientes = false;
  bool _sincronizandoProveedores = false;
  bool _sincronizandoCompras = false;
  bool _sincronizandoPedidos = false;
  bool _sincronizandoDocumentos = false;
  bool _sincronizandoComentarios = false;
  bool _sincronizandoCategorias = false;
  bool _sincronizandoListasPrecios = false;

  /// Cuando es true, los `subir*`/`eliminar*` remotos relanzan errores
  /// (usado por [SyncQueueService] para reintentos). Callers normales no cambian.
  bool _rethrowOutbound = false;

  Future<T> runOutboundStrict<T>(Future<T> Function() action) async {
    _rethrowOutbound = true;
    try {
      return await action();
    } finally {
      _rethrowOutbound = false;
    }
  }

  void _onOutboundError(Object e, String label) {
    debugPrint('$label: $e');
    if (_rethrowOutbound) {
      if (e is Exception) throw e;
      throw Exception('$label: $e');
    }
  }

  CollectionReference<Map<String, dynamic>> _col(String name) {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection(name);
  }

  CollectionReference<Map<String, dynamic>> get _ventasCol => _col('ventas');
  CollectionReference<Map<String, dynamic>> get _remitosCol => _col('remitos');
  CollectionReference<Map<String, dynamic>> get _clientesCol =>
      _col('clientes');
  CollectionReference<Map<String, dynamic>> get _proveedoresCol =>
      _col('proveedores');
  CollectionReference<Map<String, dynamic>> get _comprasCol => _col('compras');
  CollectionReference<Map<String, dynamic>> get _pedidosCol => _col('pedidos');
  CollectionReference<Map<String, dynamic>> get _documentosCol =>
      _col('documentos');
  CollectionReference<Map<String, dynamic>> get _comentariosCol =>
      _col('comentarios');
  CollectionReference<Map<String, dynamic>> get _categoriasCol =>
      _col('categorias');
  CollectionReference<Map<String, dynamic>> get _listasPreciosCol =>
      _col('listas_precios');

  String _docIdPorNombre(String nombre) {
    final n = nombre.trim().toLowerCase();
    if (n.isEmpty) return 'sin_nombre';
    return n
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñü]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> start() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    await stop();
    // Catálogo completo sin tope artificial (antes 2000 cortaba productos).
    _productosSub = _remote.watchTodos(limit: 0).listen(
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
    _clientesSub = _clientesCol.snapshots().listen(
      _aplicarClientesRemotos,
      onError: (Object error) => debugPrint('Sync clientes: $error'),
    );
    _proveedoresSub = _proveedoresCol.snapshots().listen(
      _aplicarProveedoresRemotos,
      onError: (Object error) => debugPrint('Sync proveedores: $error'),
    );
    _comprasSub = _comprasCol.snapshots().listen(
      _aplicarComprasRemotas,
      onError: (Object error) => debugPrint('Sync compras: $error'),
    );
    _pedidosSub = _pedidosCol.snapshots().listen(
      _aplicarPedidosRemotos,
      onError: (Object error) => debugPrint('Sync pedidos: $error'),
    );
    _documentosSub = _documentosCol.snapshots().listen(
      _aplicarDocumentosRemotos,
      onError: (Object error) => debugPrint('Sync documentos: $error'),
    );
    _comentariosSub = _comentariosCol.snapshots().listen(
      _aplicarComentariosRemotos,
      onError: (Object error) => debugPrint('Sync comentarios: $error'),
    );
    _categoriasSub = _categoriasCol.snapshots().listen(
      _aplicarCategoriasRemotas,
      onError: (Object error) => debugPrint('Sync categorias: $error'),
    );
    _listasPreciosSub = _listasPreciosCol.snapshots().listen(
      _aplicarListasPreciosRemotas,
      onError: (Object error) => debugPrint('Sync listas_precios: $error'),
    );
  }

  Future<void> stop() async {
    await _productosSub?.cancel();
    await _ventasSub?.cancel();
    await _remitosSub?.cancel();
    await _clientesSub?.cancel();
    await _proveedoresSub?.cancel();
    await _comprasSub?.cancel();
    await _pedidosSub?.cancel();
    await _documentosSub?.cancel();
    await _comentariosSub?.cancel();
    await _categoriasSub?.cancel();
    await _listasPreciosSub?.cancel();
    _productosSub = null;
    _ventasSub = null;
    _remitosSub = null;
    _clientesSub = null;
    _proveedoresSub = null;
    _comprasSub = null;
    _pedidosSub = null;
    _documentosSub = null;
    _comentariosSub = null;
    _categoriasSub = null;
    _listasPreciosSub = null;
  }

  ProductoRepository get writeRepository {
    // Con Firebase habilitado siempre usamos dual-write + cola, aunque
    // Auth aún no esté listo: lo local nunca se pierde.
    if (BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady) {
      return _DualProductoRepository(local: _cache, remote: _remote);
    }
    return _cache;
  }

  bool get _puedeEscribirRemoto {
    return BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady &&
        FirebaseAuthUsuarioService.instance.uidActual != null;
  }

  bool get puedeEscribirRemoto => _puedeEscribirRemoto;

  void _requireEscrituraRemota() {
    if (!_puedeEscribirRemoto && _rethrowOutbound) {
      throw StateError('Sin sesión Firebase o sync deshabilitado');
    }
  }

  Future<String> asegurarSyncIdCliente(int clienteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'clientes',
      where: 'id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    final actual = rows.first['syncId']?.toString() ?? '';
    if (actual.isNotEmpty) return actual;
    final syncId = const Uuid().v4();
    await db.update(
      'clientes',
      {'syncId': syncId},
      where: 'id = ?',
      whereArgs: [clienteId],
    );
    return syncId;
  }

  Future<String> asegurarSyncIdProveedor(int proveedorId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'proveedores',
      where: 'id = ?',
      whereArgs: [proveedorId],
      limit: 1,
    );
    if (rows.isEmpty) return '';
    final actual = rows.first['syncId']?.toString() ?? '';
    if (actual.isNotEmpty) return actual;
    final syncId = const Uuid().v4();
    await db.update(
      'proveedores',
      {'syncId': syncId},
      where: 'id = ?',
      whereArgs: [proveedorId],
    );
    return syncId;
  }

  Future<void> subirCliente(int clienteId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final syncId = await asegurarSyncIdCliente(clienteId);
      if (syncId.isEmpty) return;
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final cliente = Cliente.fromMap(rows.first);
      await _clientesCol.doc(syncId).set({
        ...cliente.toFirestore(),
        'localId': clienteId,
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir cliente');
    }
  }

  Future<void> eliminarProductoRemoto(String codigo) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto || codigo.trim().isEmpty) return;
    try {
      await FirestoreProductoRepository().eliminarPorCodigo(codigo);
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar producto');
    }
  }

  Future<void> eliminarClienteRemoto(String syncId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto || syncId.isEmpty) return;
    try {
      await _clientesCol.doc(syncId).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar cliente');
    }
  }

  Future<void> subirProveedor(int proveedorId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final syncId = await asegurarSyncIdProveedor(proveedorId);
      if (syncId.isEmpty) return;
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'proveedores',
        where: 'id = ?',
        whereArgs: [proveedorId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final proveedor = Proveedor.fromMap(rows.first);
      await _proveedoresCol.doc(syncId).set({
        ...proveedor.toFirestore(),
        'localId': proveedorId,
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir proveedor');
    }
  }

  Future<void> eliminarProveedorRemoto(String syncId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto || syncId.isEmpty) return;
    try {
      await _proveedoresCol.doc(syncId).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar proveedor');
    }
  }

  Future<void> subirCompra(int compraId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'compras',
        where: 'id = ?',
        whereArgs: [compraId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final compra = rows.first;
      final items = await db.rawQuery('''
        SELECT ci.*, p.codigo AS productoCodigo
        FROM compra_items ci
        LEFT JOIN productos p ON p.id = ci.productoId
        WHERE ci.compraId = ?
      ''', [compraId]);

      String? proveedorSyncId;
      final proveedorId = (compra['proveedorId'] as num?)?.toInt();
      if (proveedorId != null) {
        proveedorSyncId = await asegurarSyncIdProveedor(proveedorId);
        await subirProveedor(proveedorId);
      }

      final numero = compra['numero']?.toString() ?? 'C_$compraId';
      await _comprasCol.doc(numero).set({
        ...Map<String, dynamic>.from(compra)..remove('id'),
        'localId': compraId,
        'proveedorSyncId': proveedorSyncId,
        'items': items,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      for (final item in items) {
        final pid = item['productoId'];
        if (pid is int) await subirProductoPorId(pid);
      }
    } catch (e) {
      _onOutboundError(e, 'Firestore subir compra');
    }
  }

  Future<void> subirPedido(int pedidoId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'pedidos',
        where: 'id = ?',
        whereArgs: [pedidoId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final pedido = rows.first;
      final items = await db.rawQuery('''
        SELECT pi.*, p.codigo AS productoCodigo
        FROM pedido_items pi
        LEFT JOIN productos p ON p.id = pi.productoId
        WHERE pi.pedidoId = ?
        ORDER BY pi.orden ASC, pi.id ASC
      ''', [pedidoId]);

      String? proveedorSyncId;
      final proveedorId = (pedido['proveedorId'] as num?)?.toInt();
      if (proveedorId != null) {
        proveedorSyncId = await asegurarSyncIdProveedor(proveedorId);
        await subirProveedor(proveedorId);
      }

      final numero = pedido['numero']?.toString() ?? 'P_$pedidoId';
      await _pedidosCol.doc(numero).set({
        ...Map<String, dynamic>.from(pedido)..remove('id'),
        'localId': pedidoId,
        'proveedorSyncId': proveedorSyncId,
        'items': items,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir pedido');
    }
  }

  Future<void> eliminarPedidoRemoto(String numero) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto || numero.trim().isEmpty) return;
    try {
      await _pedidosCol.doc(numero).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar pedido');
    }
  }

  Future<void> subirDocumento(DocumentoCliente doc) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto || doc.id.isEmpty) return;
    try {
      await _documentosCol.doc(doc.id).set(
            doc.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      _onOutboundError(e, 'Firestore subir documento');
    }
  }

  String _comentarioDocId(ComentarioInterno c) {
    final raw =
        '${c.entidadTipo}|${c.entidadId}|${c.usuario}|${c.fecha.toUtc().toIso8601String()}|${c.texto}';
    return raw.hashCode.toUnsigned(32).toRadixString(16);
  }

  Future<void> subirComentario(ComentarioInterno c) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      await _comentariosCol.doc(_comentarioDocId(c)).set({
        'entidadTipo': c.entidadTipo,
        'entidadId': c.entidadId,
        'usuario': c.usuario,
        'nombre': c.nombre,
        'texto': c.texto,
        'fecha': c.fecha.toUtc().toIso8601String(),
        'activo': c.activo,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir comentario');
    }
  }

  Future<void> eliminarComentarioRemoto(ComentarioInterno c) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      await _comentariosCol.doc(_comentarioDocId(c)).set({
        'activo': false,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar comentario');
    }
  }

  Future<void> subirCategoria(int categoriaId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'categorias',
        where: 'id = ?',
        whereArgs: [categoriaId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final nombre = rows.first['nombre']?.toString() ?? '';
      final docId = _docIdPorNombre(nombre);
      await _categoriasCol.doc(docId).set({
        'nombre': nombre,
        'descripcion': rows.first['descripcion'] ?? '',
        'activa': rows.first['activa'] ?? 1,
        'localId': categoriaId,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir categoria');
    }
  }

  Future<void> eliminarCategoriaRemota(String nombre) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      await _categoriasCol.doc(_docIdPorNombre(nombre)).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar categoria');
    }
  }

  Future<void> _aplicarCategoriasRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoCategorias) return;
    _sincronizandoCategorias = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final nombre = data['nombre']?.toString().trim() ?? '';
        if (nombre.isEmpty) continue;
        final existentes = await db.query(
          'categorias',
          where: 'LOWER(nombre) = ?',
          whereArgs: [nombre.toLowerCase()],
          limit: 1,
        );
        final map = {
          'nombre': nombre,
          'descripcion': data['descripcion']?.toString() ?? '',
          'activa': (data['activa'] is bool)
              ? ((data['activa'] as bool) ? 1 : 0)
              : (data['activa'] ?? 1),
        };
        if (existentes.isEmpty) {
          await db.insert('categorias', map);
        } else {
          await db.update(
            'categorias',
            map,
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar categorias remotas: $e');
    } finally {
      _sincronizandoCategorias = false;
    }
  }

  Future<void> subirListaPrecio(int listaId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'listas_precios',
        where: 'id = ?',
        whereArgs: [listaId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final nombre = rows.first['nombre']?.toString() ?? '';
      final docId = _docIdPorNombre(nombre);
      await _listasPreciosCol.doc(docId).set({
        'nombre': nombre,
        'porcentaje': rows.first['porcentaje'] ?? 0,
        'activa': rows.first['activa'] ?? 1,
        'orden': rows.first['orden'] ?? 0,
        'color': rows.first['color'] ?? '',
        'prioridad': rows.first['prioridad'] ?? 0,
        'localId': listaId,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir lista_precio');
    }
  }

  Future<void> eliminarListaPrecioRemota(String nombre) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      await _listasPreciosCol.doc(_docIdPorNombre(nombre)).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar lista_precio');
    }
  }

  Future<void> _aplicarListasPreciosRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoListasPrecios) return;
    _sincronizandoListasPrecios = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final nombre = data['nombre']?.toString().trim() ?? '';
        if (nombre.isEmpty) continue;
        final existentes = await db.query(
          'listas_precios',
          where: 'LOWER(nombre) = ?',
          whereArgs: [nombre.toLowerCase()],
          limit: 1,
        );
        final map = {
          'nombre': nombre,
          'porcentaje': (data['porcentaje'] as num?)?.toDouble() ?? 0,
          'activa': (data['activa'] is bool)
              ? ((data['activa'] as bool) ? 1 : 0)
              : (data['activa'] ?? 1),
          'orden': (data['orden'] as num?)?.toInt() ?? 0,
          'color': data['color']?.toString() ?? '',
          'prioridad': (data['prioridad'] as num?)?.toInt() ?? 0,
        };
        if (existentes.isEmpty) {
          await db.insert('listas_precios', map);
        } else {
          await db.update(
            'listas_precios',
            map,
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar listas_precios remotas: $e');
    } finally {
      _sincronizandoListasPrecios = false;
    }
  }

  Future<void> _aplicarComentariosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoComentarios) return;
    _sincronizandoComentarios = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final entidadTipo = data['entidadTipo']?.toString() ?? '';
        final entidadId = data['entidadId']?.toString() ?? '';
        final usuario = data['usuario']?.toString() ?? '';
        final texto = data['texto']?.toString() ?? '';
        final fecha = data['fecha']?.toString() ?? '';
        if (entidadTipo.isEmpty || entidadId.isEmpty || texto.isEmpty) continue;
        final activo = data['activo'] != false;

        final existentes = await db.query(
          'comentarios_internos',
          where:
              'entidadTipo = ? AND entidadId = ? AND usuario = ? AND texto = ? AND activo = 1',
          whereArgs: [entidadTipo, entidadId, usuario, texto],
          orderBy: 'id DESC',
          limit: 8,
        );
        // Evitar duplicados: misma nota local vs remota (fecha local ≠ UTC).
        final fechaRemota = DateTime.tryParse(fecha)?.toUtc();
        var yaExiste = false;
        for (final row in existentes) {
          final fechaLocal =
              DateTime.tryParse(row['fecha']?.toString() ?? '')?.toUtc();
          if (fechaLocal == null || fechaRemota == null) {
            yaExiste = true;
            break;
          }
          final diff = fechaLocal.difference(fechaRemota).inSeconds.abs();
          if (diff <= 120) {
            yaExiste = true;
            break;
          }
        }
        if (!yaExiste) {
          if (!activo) continue;
          await db.insert('comentarios_internos', {
            'entidadTipo': entidadTipo,
            'entidadId': entidadId,
            'usuario': usuario,
            'nombre': data['nombre']?.toString() ?? usuario,
            'texto': texto,
            'fecha': fechaRemota?.toIso8601String() ?? fecha,
            'activo': 1,
          });
        } else if (!activo) {
          await db.update(
            'comentarios_internos',
            {'activo': 0},
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar comentarios remotos: $e');
    } finally {
      _sincronizandoComentarios = false;
    }
  }

  Future<void> subirVenta(int ventaId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT v.*, c.nombre AS clienteNombre, c.syncId AS clienteSyncId,
               c.cuit AS clienteCuit
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.id = ?
      ''', [ventaId]);
      if (rows.isEmpty) return;
      final venta = Venta.fromMap(rows.first);
      if (venta.clienteId != null) {
        await subirCliente(venta.clienteId!);
      }
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
        'clienteSyncId': rows.first['clienteSyncId'],
        'clienteCuit': rows.first['clienteCuit'],
        'items': itemsEnriquecidos,
        'pagos': pagos,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _onOutboundError(e, 'Firestore subir venta');
    }
  }

  Future<void> eliminarVentaRemota(Venta venta) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final docId = venta.numero.isNotEmpty ? venta.numero : 'v_${venta.id}';
      await _ventasCol.doc(docId).delete();
    } catch (e) {
      _onOutboundError(e, 'Firestore eliminar venta');
    }
  }

  /// Sube remito + ítems y empuja el stock actualizado de cada producto.
  Future<void> subirRemito(int remitoId) async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT r.*, c.nombre AS clienteNombre, c.syncId AS clienteSyncId,
               c.cuit AS clienteCuit
        FROM remitos r
        LEFT JOIN clientes c ON c.id = r.clienteId
        WHERE r.id = ?
      ''', [remitoId]);
      if (rows.isEmpty) return;
      final remito = rows.first;
      final clienteId = (remito['clienteId'] as num?)?.toInt();
      if (clienteId != null) {
        await subirCliente(clienteId);
      }
      final items = await db.rawQuery('''
        SELECT ri.*, p.codigo AS productoCodigo, p.descripcion AS productoDescripcion
        FROM remito_items ri
        LEFT JOIN productos p ON p.id = ri.productoId
        WHERE ri.remitoId = ?
      ''', [remitoId]);

      final numero = remito['numero']?.toString() ?? 'R_$remitoId';
      // Pagos de remito (ventaId=0, observaciones "Remito N…").
      final pagosRows = await db.query(
        'pagos',
        where: "ventaId = 0 AND observaciones LIKE ?",
        whereArgs: ['Remito $numero%'],
        orderBy: 'fecha ASC',
      );
      final pagos = pagosRows
          .map(
            (p) => {
              'fecha': p['fecha'],
              'monto': p['monto'],
              'medioPago': p['medioPago'],
              'observaciones': p['observaciones'],
              'clienteId': p['clienteId'],
            },
          )
          .toList();

      await _remitosCol.doc(numero).set({
        'numero': numero,
        'clienteId': remito['clienteId'],
        'clienteNombre': remito['clienteNombre'],
        'clienteSyncId': remito['clienteSyncId'],
        'clienteCuit': remito['clienteCuit'],
        'fecha': remito['fecha'],
        'total': remito['total'],
        'descuento': remito['descuento'],
        'estado': remito['estado'],
        'estadoPago': remito['estadoPago'],
        'totalPagado': remito['totalPagado'] ?? 0,
        'saldoPendiente': remito['saldoPendiente'] ?? remito['total'] ?? 0,
        'observaciones': remito['observaciones'],
        'fechaCreacion': remito['fechaCreacion'],
        'localId': remitoId,
        'items': items,
        'pagos': pagos,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      final productoIds =
          items.map((e) => e['productoId']).whereType<int>().toSet();
      for (final pid in productoIds) {
        await subirProductoPorId(pid);
      }
    } catch (e) {
      _onOutboundError(e, 'Firestore subir remito');
    }
  }

  Future<void> subirProductoPorId(int productoId) async {
    _requireEscrituraRemota();
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
      var producto = Producto.fromMap(rows.first);
      // Subir fotos locales a Storage para que el otro dispositivo las vea.
      final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
        producto.codigo,
        producto.todasLasFotos,
      );
      if (fotos.isNotEmpty && fotos.join('|') != producto.todasLasFotos.join('|')) {
        producto = producto.copyWith(
          foto: fotos.first,
          fotos: fotos,
        );
        await db.update(
          'productos',
          {
            'foto': producto.fotoPrincipal,
            'fotos': producto.toMap()['fotos'],
          },
          where: 'id = ?',
          whereArgs: [productoId],
        );
      }
      await _remote.actualizar(producto);
    } catch (e) {
      _onOutboundError(e, 'Firestore subir producto');
    }
  }

  /// Sube todo el catálogo local activo a Firestore (por lotes).
  /// Útil cuando un dispositivo tiene productos que nunca llegaron a la nube.
  Future<int> subirCatalogoLocalCompleto() async {
    _requireEscrituraRemota();
    if (!_puedeEscribirRemoto) {
      throw StateError('Sin sesión en la nube');
    }
    final locales = await _cache.obtenerTodos();
    if (locales.isEmpty) return 0;
    final listos = <Producto>[];
    for (final p in locales) {
      final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
        p.codigo,
        p.todasLasFotos,
      );
      if (fotos.isNotEmpty && fotos.join('|') != p.todasLasFotos.join('|')) {
        final actualizado = p.copyWith(foto: fotos.first, fotos: fotos);
        listos.add(actualizado);
        if (p.id != null) {
          await _cache.actualizar(actualizado);
        }
      } else {
        listos.add(p);
      }
    }
    await _remote.insertarLista(listos);
    return listos.length;
  }

  Future<int?> _resolverClienteLocal({
    required Database db,
    String? syncId,
    String? cuit,
    String? nombre,
  }) async {
    if (syncId != null && syncId.isNotEmpty) {
      final bySync = await db.query(
        'clientes',
        where: 'syncId = ?',
        whereArgs: [syncId],
        limit: 1,
      );
      if (bySync.isNotEmpty) return bySync.first['id'] as int?;
    }
    if (cuit != null && cuit.trim().isNotEmpty) {
      final byCuit = await db.query(
        'clientes',
        where: 'cuit = ?',
        whereArgs: [cuit.trim()],
        limit: 1,
      );
      if (byCuit.isNotEmpty) return byCuit.first['id'] as int?;
    }
    if (nombre != null && nombre.trim().isNotEmpty) {
      final byNombre = await db.query(
        'clientes',
        where: 'nombre = ?',
        whereArgs: [nombre.trim()],
        limit: 1,
      );
      if (byNombre.isNotEmpty) return byNombre.first['id'] as int?;
    }
    return null;
  }

  Future<void> _aplicarClientesRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoClientes) return;
    _sincronizandoClientes = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final syncId = data['syncId']?.toString().isNotEmpty == true
            ? data['syncId'].toString()
            : doc.id;
        final map = Map<String, dynamic>.from(data)
          ..remove('localId')
          ..remove('actualizadoEn')
          ..remove('id');
        map['syncId'] = syncId;

        final existentes = await db.query(
          'clientes',
          where: 'syncId = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existentes.isEmpty) {
          final cuit = map['cuit']?.toString() ?? '';
          final nombre = map['nombre']?.toString() ?? '';
          final porCuit = cuit.isNotEmpty
              ? await db.query(
                  'clientes',
                  where: 'cuit = ?',
                  whereArgs: [cuit],
                  limit: 1,
                )
              : <Map<String, dynamic>>[];
          final porNombre = porCuit.isEmpty && nombre.isNotEmpty
              ? await db.query(
                  'clientes',
                  where: 'nombre = ? AND (syncId IS NULL OR syncId = "")',
                  whereArgs: [nombre],
                  limit: 1,
                )
              : <Map<String, dynamic>>[];
          final match =
              porCuit.isNotEmpty ? porCuit.first : (porNombre.isNotEmpty ? porNombre.first : null);
          if (match != null) {
            await db.update(
              'clientes',
              map,
              where: 'id = ?',
              whereArgs: [match['id']],
            );
          } else {
            await db.insert('clientes', map..remove('id'));
          }
        } else {
          await db.update(
            'clientes',
            map..remove('id'),
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar clientes remotos: $e');
    } finally {
      _sincronizandoClientes = false;
    }
  }

  Future<void> _aplicarProveedoresRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoProveedores) return;
    _sincronizandoProveedores = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final syncId = data['syncId']?.toString().isNotEmpty == true
            ? data['syncId'].toString()
            : doc.id;
        final map = Map<String, dynamic>.from(data)
          ..remove('localId')
          ..remove('actualizadoEn')
          ..remove('id');
        map['syncId'] = syncId;
        if (map['activo'] is bool) {
          map['activo'] = (map['activo'] as bool) ? 1 : 0;
        }

        final existentes = await db.query(
          'proveedores',
          where: 'syncId = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existentes.isEmpty) {
          final nombre = map['nombre']?.toString() ?? '';
          final match = nombre.isNotEmpty
              ? await db.query(
                  'proveedores',
                  where: 'nombre = ? AND (syncId IS NULL OR syncId = "")',
                  whereArgs: [nombre],
                  limit: 1,
                )
              : <Map<String, dynamic>>[];
          if (match.isNotEmpty) {
            await db.update(
              'proveedores',
              map,
              where: 'id = ?',
              whereArgs: [match.first['id']],
            );
          } else {
            await db.insert('proveedores', map..remove('id'));
          }
        } else {
          await db.update(
            'proveedores',
            map..remove('id'),
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar proveedores remotos: $e');
    } finally {
      _sincronizandoProveedores = false;
    }
  }

  Future<void> _aplicarComprasRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoCompras) return;
    _sincronizandoCompras = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        final existentes = await db.query(
          'compras',
          where: 'numero = ?',
          whereArgs: [numero],
          limit: 1,
        );

        int? proveedorId = (data['proveedorId'] as num?)?.toInt();
        final proveedorSyncId = data['proveedorSyncId']?.toString();
        if (proveedorSyncId != null && proveedorSyncId.isNotEmpty) {
          final prov = await db.query(
            'proveedores',
            where: 'syncId = ?',
            whereArgs: [proveedorSyncId],
            limit: 1,
          );
          if (prov.isNotEmpty) proveedorId = prov.first['id'] as int?;
        }

        final compraMap = <String, dynamic>{
          'proveedorId': proveedorId,
          'proveedorNombre': data['proveedorNombre'],
          'numero': numero,
          'factura': data['factura'],
          'fecha': data['fecha'],
          'total': data['total'] ?? 0,
          'descuento': data['descuento'] ?? 0,
          'iva': data['iva'] ?? 0,
          'observaciones': data['observaciones'] ?? '',
          'fechaCreacion':
              data['fechaCreacion'] ?? DateTime.now().toIso8601String(),
          'estado': data['estado'] ?? 'confirmada',
        };

        final int compraId;
        if (existentes.isEmpty) {
          compraId = await db.insert('compras', compraMap);
        } else {
          compraId = existentes.first['id'] as int;
          await db.update(
            'compras',
            compraMap,
            where: 'id = ?',
            whereArgs: [compraId],
          );
          await db.delete(
            'compra_items',
            where: 'compraId = ?',
            whereArgs: [compraId],
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
            if (prod.isNotEmpty) productoId = prod.first['id'] as int?;
          }
          if (productoId == null) continue;
          await db.insert('compra_items', {
            'compraId': compraId,
            'productoId': productoId,
            'productoDescripcion': item['productoDescripcion'] ?? '',
            'cantidad': item['cantidad'] ?? 0,
            'costo': item['costo'] ?? 0,
            'subtotal': item['subtotal'] ?? 0,
          });
        }
        // Stock llega por sync de productos.
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar compras remotas: $e');
    } finally {
      _sincronizandoCompras = false;
    }
  }

  Future<void> _aplicarPedidosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoPedidos) return;
    _sincronizandoPedidos = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        final existentes = await db.query(
          'pedidos',
          where: 'numero = ?',
          whereArgs: [numero],
          limit: 1,
        );

        int? proveedorId = (data['proveedorId'] as num?)?.toInt();
        final proveedorSyncId = data['proveedorSyncId']?.toString();
        if (proveedorSyncId != null && proveedorSyncId.isNotEmpty) {
          final prov = await db.query(
            'proveedores',
            where: 'syncId = ?',
            whereArgs: [proveedorSyncId],
            limit: 1,
          );
          if (prov.isNotEmpty) proveedorId = prov.first['id'] as int?;
        }

        final pedidoMap = <String, dynamic>{
          'proveedorId': proveedorId,
          'proveedorNombre': data['proveedorNombre'] ?? '',
          'numero': numero,
          'fecha': data['fecha'] ?? DateTime.now().toIso8601String(),
          'observaciones': data['observaciones'] ?? '',
          'estado': data['estado'] ?? 'borrador',
          'fechaCreacion':
              data['fechaCreacion'] ?? DateTime.now().toIso8601String(),
          'fechaActualizacion': data['fechaActualizacion'] ??
              data['actualizadoEn'] ??
              DateTime.now().toIso8601String(),
        };

        final int pedidoId;
        if (existentes.isEmpty) {
          pedidoId = await db.insert('pedidos', pedidoMap);
        } else {
          pedidoId = existentes.first['id'] as int;
          await db.update(
            'pedidos',
            pedidoMap,
            where: 'id = ?',
            whereArgs: [pedidoId],
          );
          await db.delete(
            'pedido_items',
            where: 'pedidoId = ?',
            whereArgs: [pedidoId],
          );
        }

        final items = (data['items'] as List?) ?? const [];
        for (var i = 0; i < items.length; i++) {
          final raw = items[i];
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
            if (prod.isNotEmpty) productoId = prod.first['id'] as int?;
          }
          final articulo = item['articulo']?.toString() ?? '';
          if (articulo.trim().isEmpty) continue;
          await db.insert('pedido_items', {
            'pedidoId': pedidoId,
            'productoId': productoId,
            'articulo': articulo,
            'cantidad': item['cantidad'] ?? 1,
            'color': item['color'] ?? '',
            'observaciones': item['observaciones'] ?? '',
            'orden': item['orden'] ?? i,
          });
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar pedidos remotos: $e');
    } finally {
      _sincronizandoPedidos = false;
    }
  }

  Future<void> _aplicarDocumentosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoDocumentos) return;
    _sincronizandoDocumentos = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final doc in snap.docs) {
        final data = doc.data();
        final id = data['id']?.toString() ?? doc.id;
        final map = Map<String, dynamic>.from(data)
          ..remove('actualizadoEn');
        map['id'] = id;

        final existentes = await db.query(
          'documentos_cliente',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existentes.isEmpty) {
          await db.insert('documentos_cliente', map);
        } else {
          await db.update(
            'documentos_cliente',
            map,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar documentos remotos: $e');
    } finally {
      _sincronizandoDocumentos = false;
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

        final clienteId = await _resolverClienteLocal(
          db: db,
          syncId: data['clienteSyncId']?.toString(),
          cuit: data['clienteCuit']?.toString(),
          nombre: data['clienteNombre']?.toString(),
        );

        final remitoMap = <String, dynamic>{
          'numero': numero,
          'clienteId': clienteId,
          'fecha': data['fecha'],
          'total': data['total'] ?? 0,
          'descuento': data['descuento'] ?? 0,
          'estado': data['estado'] ?? 'confirmado',
          'estadoPago': data['estadoPago'] ?? 'pendiente',
          'totalPagado': data['totalPagado'] ?? 0,
          'saldoPendiente': data['saldoPendiente'] ?? data['total'] ?? 0,
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

        // Reemplazar pagos locales del remito por los remotos.
        await db.delete(
          'pagos',
          where: "ventaId = 0 AND observaciones LIKE ?",
          whereArgs: ['Remito $numero%'],
        );
        final pagosRemotos = (data['pagos'] as List?) ?? const [];
        for (final raw in pagosRemotos) {
          final pago = Map<String, dynamic>.from(raw as Map);
          await db.insert('pagos', {
            'ventaId': 0,
            'clienteId': clienteId ?? pago['clienteId'],
            'fecha': pago['fecha'] ?? DateTime.now().toIso8601String(),
            'monto': pago['monto'] ?? 0,
            'medioPago': pago['medioPago'] ?? 'efectivo',
            'observaciones': pago['observaciones'] ?? 'Remito $numero',
          });
        }
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
      final clientesAfectados = <int>{};
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
          ..remove('clienteSyncId')
          ..remove('clienteCuit')
          ..remove('actualizadoEn')
          ..remove('id');

        final clienteId = await _resolverClienteLocal(
          db: db,
          syncId: data['clienteSyncId']?.toString(),
          cuit: data['clienteCuit']?.toString(),
          nombre: data['clienteNombre']?.toString(),
        );
        if (clienteId != null) map['clienteId'] = clienteId;

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
        if (clienteId != null) {
          clientesAfectados.add(clienteId);
        }
      }
      for (final cid in clientesAfectados) {
        try {
          await CuentaCorrienteService().recalcularSaldoCliente(cid);
        } catch (e) {
          debugPrint('Recalc saldo cliente $cid: $e');
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

  bool get _remotoOk => FirestoreSyncService.instance.puedeEscribirRemoto;

  Future<void> _encolarProducto(int id) {
    return SyncQueueService.instance.enqueueUpsert('producto', id);
  }

  @override
  Future<int> insertar(Producto producto) async {
    final id = await local.insertar(producto);
    final conId = producto.copyWith(id: id);
    if (_remotoOk) {
      try {
        await remote.insertar(conId);
        return id;
      } catch (error) {
        debugPrint('Firestore insertar producto: $error');
      }
    }
    await _encolarProducto(id);
    return id;
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    await local.insertarLista(productos);
    if (_remotoOk) {
      try {
        await remote.insertarLista(productos);
        return;
      } catch (error) {
        debugPrint('Firestore insertarLista productos: $error');
      }
    }
    // Sin remoto o fallo: encolar cada ítem por código local.
    for (final p in productos) {
      final localP = await local.buscarPorCodigo(p.codigo);
      if (localP?.id != null) {
        await _encolarProducto(localP!.id!);
      }
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
    final id = producto.id;
    if (id == null) return result;
    if (_remotoOk) {
      try {
        await remote.actualizar(producto);
        return result;
      } catch (error) {
        debugPrint('Firestore actualizar producto: $error');
      }
    }
    await _encolarProducto(id);
    return result;
  }

  @override
  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows =
        await db.query('productos', where: 'id = ?', whereArgs: [id], limit: 1);
    final result = await local.eliminar(id);
    if (rows.isEmpty) return result;
    final producto = Producto.fromMap(rows.first).copyWith(
      deletedAt: DateTime.now().toIso8601String(),
      favorito: false,
    );
    if (_remotoOk) {
      try {
        await remote.actualizar(producto);
        return result;
      } catch (error) {
        debugPrint('Firestore soft-delete producto: $error');
      }
    }
    await _encolarProducto(id);
    return result;
  }

  @override
  Stream<List<Producto>> watchTodos({int limit = 200}) =>
      remote.watchTodos(limit: limit);
}
