import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';
import 'media_sync_service.dart';
import '../../database/database_helper.dart';
import '../../models/cliente.dart';
import '../../models/documento_cliente.dart';
import '../../models/producto.dart';
import '../../models/proveedor.dart';
import '../../models/usuario.dart';
import '../../models/venta.dart';
import '../../repositories/firestore_producto_repository.dart';
import '../../repositories/firestore_usuario_repository.dart';
import '../../repositories/producto_repository.dart';
import '../../repositories/sqlite_producto_repository.dart';
import '../../repositories/sqlite_usuario_repository.dart';
import '../../services/branding_service.dart';
import '../../services/permisos_service.dart';

/// Mantiene SQLite sincronizado con Firestore en tiempo real.
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirestoreSyncService instance = FirestoreSyncService._();

  /// Lo registra AuthService para actualizar la sesión sin import circular.
  void Function(Usuario remoto)? onUsuarioRemoto;

  final SqliteProductoRepository _cache = SqliteProductoRepository();
  final FirestoreProductoRepository _remote = FirestoreProductoRepository();
  final FirestoreUsuarioRepository _usuariosRemote = FirestoreUsuarioRepository();
  final SqliteUsuarioRepository _usuariosLocal = SqliteUsuarioRepository();

  StreamSubscription<List<Producto>>? _productosSub;
  StreamSubscription<List<Usuario>>? _usuariosSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _brandingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permisosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ventasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remitosSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clientesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _proveedoresSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _comprasSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _documentosSub;

  bool _sincronizando = false;
  bool _sincronizandoVentas = false;
  bool _sincronizandoRemitos = false;
  bool _sincronizandoClientes = false;
  bool _sincronizandoProveedores = false;
  bool _sincronizandoCompras = false;
  bool _sincronizandoDocumentos = false;
  bool _sincronizandoUsuarios = false;
  bool _sincronizandoBranding = false;
  bool _sincronizandoPermisos = false;

  /// Último estado legible para la UI (sin carteles rojos agresivos).
  String syncStatusLabel = 'Local';
  String? syncStatusDetail;

  CollectionReference<Map<String, dynamic>> _col(String name) {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection(name);
  }

  DocumentReference<Map<String, dynamic>> _configDoc(String id) {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection('config')
        .doc(id);
  }

  CollectionReference<Map<String, dynamic>> get _ventasCol => _col('ventas');
  CollectionReference<Map<String, dynamic>> get _remitosCol => _col('remitos');
  CollectionReference<Map<String, dynamic>> get _clientesCol =>
      _col('clientes');
  CollectionReference<Map<String, dynamic>> get _proveedoresCol =>
      _col('proveedores');
  CollectionReference<Map<String, dynamic>> get _comprasCol => _col('compras');
  CollectionReference<Map<String, dynamic>> get _documentosCol =>
      _col('documentos');

  Future<void> start() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      syncStatusLabel = 'Solo local';
      syncStatusDetail = null;
      return;
    }
    try {
      await stop();
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail = null;

      _productosSub = _remote.watchTodos(limit: 10000).listen(
        _aplicarProductosRemotos,
        onError: (Object error) => debugPrint('Sync productos: $error'),
      );
      _usuariosSub = _usuariosRemote.watchTodos().listen(
        _aplicarUsuariosRemotos,
        onError: (Object error) => debugPrint('Sync usuarios: $error'),
      );
      _brandingSub = _configDoc('branding').snapshots().listen(
        _aplicarBrandingRemoto,
        onError: (Object error) => debugPrint('Sync branding: $error'),
      );
      _permisosSub = _configDoc('permisos').snapshots().listen(
        _aplicarPermisosRemotos,
        onError: (Object error) => debugPrint('Sync permisos: $error'),
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
      _documentosSub = _documentosCol.snapshots().listen(
        _aplicarDocumentosRemotos,
        onError: (Object error) => debugPrint('Sync documentos: $error'),
      );

      unawaited(_reintentarFotosLocalesPendientes());
      // Empuja branding/permisos locales la primera vez si la nube no tiene.
      unawaited(_publicarConfigLocalSiHaceFalta());

      syncStatusLabel = 'En la nube';
      DataRefreshHub.instance.notifyTodo();
    } catch (e, st) {
      syncStatusLabel = 'Local';
      syncStatusDetail = '$e';
      debugPrint('FirestoreSyncService.start falló: $e\n$st');
    }
  }

  Future<void> _reintentarFotosLocalesPendientes() async {
    if (!_puedeEscribirRemoto) return;
    try {
      final todos = await _cache.obtenerTodos(limit: 10000);
      for (final p in todos) {
        if (p.id == null) continue;
        final locales = p.todasLasFotos.where((f) {
          if (f.isEmpty || esUrlRemota(f)) return false;
          try {
            return File(f).existsSync();
          } catch (_) {
            return false;
          }
        }).toList();
        if (locales.isEmpty) continue;
        await subirProductoPorId(p.id!);
      }
    } catch (e) {
      debugPrint('Reintento fotos locales: $e');
    }
  }

  Future<void> stop() async {
    await _productosSub?.cancel();
    await _usuariosSub?.cancel();
    await _brandingSub?.cancel();
    await _permisosSub?.cancel();
    await _ventasSub?.cancel();
    await _remitosSub?.cancel();
    await _clientesSub?.cancel();
    await _proveedoresSub?.cancel();
    await _comprasSub?.cancel();
    await _documentosSub?.cancel();
    _productosSub = null;
    _usuariosSub = null;
    _brandingSub = null;
    _permisosSub = null;
    _ventasSub = null;
    _remitosSub = null;
    _clientesSub = null;
    _proveedoresSub = null;
    _comprasSub = null;
    _documentosSub = null;
  }

  Future<void> _publicarConfigLocalSiHaceFalta() async {
    if (!_puedeEscribirRemoto) return;
    try {
      final brandingSnap = await _configDoc('branding').get();
      if (!brandingSnap.exists) {
        await subirBranding();
      }
      final permisosSnap = await _configDoc('permisos').get();
      if (!permisosSnap.exists) {
        await subirPermisos();
      }
    } catch (e) {
      debugPrint('Publicar config local: $e');
    }
  }

  Future<void> subirBranding() async {
    if (!_puedeEscribirRemoto) return;
    try {
      final payload = await BrandingService.instance.prepararPayloadNube();
      await _configDoc('branding').set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore subir branding: $e');
      rethrow;
    }
  }

  Future<void> subirPermisos() async {
    if (!_puedeEscribirRemoto) return;
    try {
      final items = await PermisosService.instance.exportarParaFirestore();
      await _configDoc('permisos').set({
        'items': items,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore subir permisos: $e');
      rethrow;
    }
  }

  Future<void> subirUsuario(Usuario usuario) async {
    if (!_puedeEscribirRemoto) return;
    var u = usuario;
    final uidAuth = FirebaseAuthUsuarioService.instance.uidActual;
    if ((u.firebaseUid == null || u.firebaseUid!.isEmpty) && uidAuth != null) {
      u = u.copyWith(firebaseUid: uidAuth);
    }
    if (u.firebaseUid == null || u.firebaseUid!.isEmpty) {
      throw Exception(
        'No hay sesión de nube. Activá sincronización e iniciá sesión de nuevo.',
      );
    }
    // Solo URLs de foto a Firestore
    var foto = u.foto;
    if (foto.isNotEmpty && !esUrlRemota(foto)) {
      final file = File(foto);
      if (file.existsSync()) {
        final url = await MediaSyncService.instance.subirFotoUsuario(
          uidOrUsuario: u.firebaseUid!,
          file: file,
        );
        if (url == null) {
          throw Exception(
            'No se pudo subir la foto de perfil. '
            '${MediaSyncService.instance.lastError ?? ""}',
          );
        }
        foto = url;
        u = u.copyWith(foto: foto);
        await _usuariosLocal.actualizar(u);
      } else {
        foto = '';
        u = u.copyWith(foto: '');
      }
    }
    await _usuariosRemote.actualizar(u.copyWith(foto: foto));
  }

  Future<void> _aplicarUsuariosRemotos(List<Usuario> remotos) async {
    if (_sincronizandoUsuarios) return;
    _sincronizandoUsuarios = true;
    try {
      for (final remoto in remotos) {
        // Si el remoto trae hash de password (p. ej. reset del admin), se aplica.
        // Si viene vacío, upsertDesdeRemoto conserva el hash local.
        final merged = await _usuariosLocal.upsertDesdeRemoto(remoto);
        onUsuarioRemoto?.call(merged);
      }
      DataRefreshHub.instance.notifyUsuarios();
    } catch (e) {
      debugPrint('Aplicar usuarios remotos: $e');
    } finally {
      _sincronizandoUsuarios = false;
    }
  }

  Future<void> _aplicarBrandingRemoto(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoBranding || !snap.exists) return;
    _sincronizandoBranding = true;
    try {
      final data = snap.data();
      if (data == null || data.isEmpty) return;
      await BrandingService.instance.aplicarDesdeFirestore(data);
      DataRefreshHub.instance.notifyBranding();
    } catch (e) {
      debugPrint('Aplicar branding remoto: $e');
    } finally {
      _sincronizandoBranding = false;
    }
  }

  Future<void> _aplicarPermisosRemotos(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoPermisos || !snap.exists) return;
    _sincronizandoPermisos = true;
    try {
      final data = snap.data();
      final raw = data?['items'];
      if (raw is! List || raw.isEmpty) return;
      final items = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await PermisosService.instance.aplicarDesdeRemoto(items);
      DataRefreshHub.instance.notifyPermisos();
    } catch (e) {
      debugPrint('Aplicar permisos remotos: $e');
    } finally {
      _sincronizandoPermisos = false;
    }
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
      debugPrint('Firestore subir cliente: $e');
    }
  }

  Future<void> eliminarClienteRemoto(String syncId) async {
    if (!_puedeEscribirRemoto || syncId.isEmpty) return;
    try {
      await _clientesCol.doc(syncId).delete();
    } catch (e) {
      debugPrint('Firestore eliminar cliente: $e');
    }
  }

  Future<void> subirProveedor(int proveedorId) async {
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
      debugPrint('Firestore subir proveedor: $e');
    }
  }

  Future<void> eliminarProveedorRemoto(String syncId) async {
    if (!_puedeEscribirRemoto || syncId.isEmpty) return;
    try {
      await _proveedoresCol.doc(syncId).delete();
    } catch (e) {
      debugPrint('Firestore eliminar proveedor: $e');
    }
  }

  Future<void> subirCompra(int compraId) async {
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
      debugPrint('Firestore subir compra: $e');
    }
  }

  Future<void> subirDocumento(DocumentoCliente doc) async {
    if (!_puedeEscribirRemoto || doc.id.isEmpty) return;
    try {
      await _documentosCol.doc(doc.id).set(
            doc.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Firestore subir documento: $e');
    }
  }

  Future<void> subirVenta(int ventaId) async {
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
      var producto = Producto.fromMap(rows.first);

      // Subir fotos locales a Storage antes de empujar a Firestore
      // (evita sincronizar rutas C:\... o /data/... al otro dispositivo).
      final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
        producto.codigo,
        producto.todasLasFotos,
      );
      if (fotos.isNotEmpty &&
          (fotos.first != producto.fotoPrincipal ||
              fotos.length != producto.todasLasFotos.length)) {
        producto = producto.copyWith(foto: fotos.first, fotos: fotos);
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
      debugPrint('Firestore subir producto $productoId: $e');
    }
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
      var huboCambios = false;
      for (final doc in snap.docs) {
        try {
          final data = doc.data();
          final numero = data['numero']?.toString() ?? doc.id;
          if (numero.isEmpty) continue;

          final existentes = await db.query(
            'ventas',
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

          final map = <String, dynamic>{
            'tipo': data['tipo'] ?? 'factura_b',
            'numero': numero,
            'clienteId': clienteId,
            'fecha': data['fecha'],
            'fechaVencimiento': data['fechaVencimiento'],
            'total': data['total'] ?? 0,
            'descuento': data['descuento'] ?? 0,
            'iva': data['iva'] ?? 0,
            'estado': data['estado'] ?? 'confirmada',
            'estadoPago': data['estadoPago'] ?? 'pendiente',
            'totalPagado': data['totalPagado'] ?? 0,
            'saldoPendiente': data['saldoPendiente'] ?? 0,
            'estadoAfip': data['estadoAfip'] ?? 'no_aplica',
            'cae': data['cae']?.toString() ?? '',
            'caeVencimiento': data['caeVencimiento'],
            'puntoVenta': (data['puntoVenta'] as num?)?.toInt() ?? 0,
            'observaciones': data['observaciones'] ?? '',
            'fechaCreacion':
                data['fechaCreacion'] ?? DateTime.now().toIso8601String(),
            'usuarioId': (data['usuarioId'] as num?)?.toInt(),
          };

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
            // Si el producto no existe en esta PC, igual guardamos la línea
            // con el id remoto (sin FK estricta) para no perder la venta.
            if (productoId == null) continue;

            await db.insert('ventas_items', {
              'ventaId': ventaId,
              'productoId': productoId,
              'productoDescripcion':
                  item['productoDescripcion']?.toString() ?? '',
              'cantidad': item['cantidad'] ?? 0,
              'precio': item['precio'] ?? 0,
              'subtotal': item['subtotal'] ?? 0,
              'costoUnitario': item['costoUnitario'] ?? 0,
              'ganancia': item['ganancia'] ?? 0,
            });
          }

          final pagos = (data['pagos'] as List?) ?? const [];
          for (final raw in pagos) {
            final pago = Map<String, dynamic>.from(raw as Map);
            await db.insert('pagos', {
              'ventaId': ventaId,
              'clienteId':
                  (pago['clienteId'] as num?)?.toInt() ?? clienteId,
              'fecha': pago['fecha'] ?? DateTime.now().toIso8601String(),
              'monto': pago['monto'] ?? 0,
              'medioPago': pago['medioPago'] ?? 'efectivo',
              'observaciones': pago['observaciones'] ?? '',
            });
          }
          huboCambios = true;
        } catch (e) {
          debugPrint('Aplicar venta remota ${doc.id}: $e');
        }
      }
      if (huboCambios) {
        DataRefreshHub.instance.notifyVentas();
      }
    } catch (e) {
      debugPrint('Aplicar ventas remotas: $e');
    } finally {
      _sincronizandoVentas = false;
    }
  }

  /// Evita guardar en SQLite rutas locales de OTRO dispositivo (foto rota).
  Producto _fusionarProductoRemoto(Producto remoto, Producto? local) {
    final urls = remoto.todasLasFotos.where(esUrlRemota).toList();
    if (urls.isNotEmpty) {
      return remoto.copyWith(
        id: local?.id,
        foto: urls.first,
        fotos: urls,
      );
    }
    if (local != null) {
      final localesUsables = local.todasLasFotos.where((f) {
        if (f.isEmpty) return false;
        if (esUrlRemota(f)) return true;
        try {
          return File(f).existsSync();
        } catch (_) {
          return false;
        }
      }).toList();
      if (localesUsables.isNotEmpty) {
        return remoto.copyWith(
          id: local.id,
          foto: localesUsables.first,
          fotos: localesUsables,
        );
      }
    }
    return remoto.copyWith(id: local?.id, foto: '', fotos: <String>[]);
  }

  Future<void> _aplicarProductosRemotos(List<Producto> remotos) async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final batch = db.batch();
      var huboCambios = false;
      for (final producto in remotos) {
        final local = await _cache.buscarPorCodigo(producto.codigo);
        final merged = _fusionarProductoRemoto(producto, local);
        // Evitar pisar datos locales idénticos (reduce flicker).
        if (local != null &&
            local.costo == merged.costo &&
            local.precio == merged.precio &&
            local.stock == merged.stock &&
            local.fotoPrincipal == merged.fotoPrincipal &&
            local.descripcion == merged.descripcion) {
          continue;
        }
        huboCambios = true;
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
      if (huboCambios) {
        await batch.commit(noResult: true);
        DataRefreshHub.instance.notifyProductos();
      }
    } finally {
      _sincronizando = false;
    }
  }
}

class _DualProductoRepository implements ProductoRepository {
  _DualProductoRepository({required this.local, required this.remote});

  final SqliteProductoRepository local;
  final FirestoreProductoRepository remote;

  /// Sube fotos a Storage y deja en Firestore solo URLs https.
  /// Nunca manda fotos vacías (preserva las URLs ya publicadas).
  Future<Producto> _paraFirestore(Producto producto) async {
    final sincronizado = await MediaSyncService.instance.sincronizarFotosProducto(
      producto.codigo,
      producto.todasLasFotos,
    );
    var actual = producto;
    if (sincronizado.isNotEmpty) {
      actual = producto.copyWith(
        foto: sincronizado.first,
        fotos: sincronizado,
      );
      final huboUrl = sincronizado.any(esUrlRemota);
      if (huboUrl && actual.id != null) {
        try {
          await local.actualizar(actual);
        } catch (_) {}
      }
    }
    final urls = MediaSyncService.instance.soloUrlsRemotas(actual.todasLasFotos);
    if (urls.isNotEmpty) {
      return actual.copyWith(foto: urls.first, fotos: urls);
    }
    try {
      final remoto = await remote.buscarPorCodigo(producto.codigo);
      final urlsRemotas =
          remoto?.todasLasFotos.where(esUrlRemota).toList() ?? const [];
      if (urlsRemotas.isNotEmpty) {
        // Conservar URLs previas en la nube; local puede seguir con path.
        return actual.copyWith(
          foto: urlsRemotas.first,
          fotos: urlsRemotas,
        );
      }
    } catch (_) {}
    // Sin URLs nuevas ni previas: devolver tal cual.
    // toFirestore() omitirá foto/fotos y no borrará nada en merge.
    return actual;
  }

  @override
  Future<int> insertar(Producto producto) async {
    final id = await local.insertar(producto);
    final conId = producto.copyWith(id: id);
    try {
      await remote.insertar(await _paraFirestore(conId));
    } catch (error) {
      debugPrint('Firestore insertar producto: $error');
    }
    return id;
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    await local.insertarLista(productos);
    try {
      final remotos = <Producto>[];
      for (final p in productos) {
        remotos.add(await _paraFirestore(p));
      }
      await remote.insertarLista(remotos);
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
      await remote.actualizar(await _paraFirestore(producto));
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
