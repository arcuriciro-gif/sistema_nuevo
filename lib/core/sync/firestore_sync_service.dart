import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../config/platform_capabilities.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';
import 'media_sync_service.dart';
import 'cloud_sync_throttle.dart';
import 'sync_background.dart';
import 'sync_catchup.dart';
import 'sync_health.dart';
import 'sync_outbox.dart';
import 'sync_tombstone.dart';
import 'sync_watermark_store.dart';
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
  final SqliteUsuarioRepository _usuariosLocal = SqliteUsuarioRepository();

  // Lazy: construir repos Firestore recién cuando hay nube (evita [core/no-app]).
  FirestoreProductoRepository? _remoteOrNull;
  FirestoreUsuarioRepository? _usuariosRemoteOrNull;
  FirestoreProductoRepository get _remote =>
      _remoteOrNull ??= FirestoreProductoRepository();
  FirestoreUsuarioRepository get _usuariosRemote =>
      _usuariosRemoteOrNull ??= FirestoreUsuarioRepository();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productosSub;
  StreamSubscription<List<Usuario>>? _usuariosSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _brandingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permisosSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _listasSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _categoriasSub;
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
  QuerySnapshot<Map<String, dynamic>>? _snapClientesPendiente;
  QuerySnapshot<Map<String, dynamic>>? _snapProveedoresPendiente;
  QuerySnapshot<Map<String, dynamic>>? _snapVentasPendiente;
  QuerySnapshot<Map<String, dynamic>>? _snapRemitosPendiente;
  QuerySnapshot<Map<String, dynamic>>? _snapComprasPendiente;
  QuerySnapshot<Map<String, dynamic>>? _snapDocumentosPendiente;
  List<Producto>? _productosPendientes;
  /// syncIds que ya vimos en la nube (para borrar locales solo si desaparecen de ahí).
  final Set<String> _clientesConfirmadosEnNube = {};
  /// Números de remito ya vistos en la nube (borrado remoto → borrar local).
  final Set<String> _remitosConfirmadosEnNube = {};

  /// Entidades creadas/editadas sin sesión de nube (colas persistentes).
  final Set<int> _colaClientes = {};
  final Set<int> _colaProveedores = {};
  final Set<int> _colaVentas = {};
  final Set<int> _colaRemitos = {};
  final Set<int> _colaProductos = {};
  final Set<int> _colaCompras = {};
  /// Deltas de stock pendientes: "opId|codigo|delta"
  final List<String> _colaStockOps = [];

  /// Último estado legible para la UI (sin carteles rojos agresivos).
  String syncStatusLabel = 'Local';
  String? syncStatusDetail;

  /// Reintento suave de outbox mientras la nube está activa (EXE→APK).
  Timer? _outboxPump;

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
      SyncHealthService.instance.firebaseReady = false;
      SyncHealthService.instance.canWrite = false;
      return;
    }
    try {
      await stop();
      await _cargarColasPersistidas();
      await SyncOutbox.instance.reclaimStaleInflight();
      await _migrateLegacyColasToOutbox();
      await _cargarWatermarksPersistidos();
      SyncHealthService.instance.firebaseReady = true;
      SyncHealthService.instance.canWrite = _puedeEscribirRemoto;
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail = null;

      // Solo cambios del snapshot (no reaplicar 10k productos en cada remito:
      // en Windows eso podía cerrar el .exe por presión de memoria/UI).
      _productosSub = _remote.watchSnapshots(limit: 10000).listen(
        _onProductosSnapshot,
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
      _listasSub = _configDoc('listas_precios').snapshots().listen(
        _aplicarListasPreciosRemotas,
        onError: (Object error) => debugPrint('Sync listas: $error'),
      );
      _categoriasSub = _configDoc('categorias').snapshots().listen(
        _aplicarCategoriasRemotas,
        onError: (Object error) => debugPrint('Sync categorias: $error'),
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

      // Windows: pull + upload masivo NO en el hilo de UI (cerraba el .exe).
      if (PlatformCapabilities.isWindowsDesktop) {
        syncStatusLabel = 'Sincronizando…';
        syncStatusDetail =
            'Conectado. Bajando y subiendo datos en segundo plano…';
        DataRefreshHub.instance.notifyTodo();
        _iniciarOutboxPump();
        syncInBackground(
          CloudSyncThrottle.enqueue(() async {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            await _pullInicialCatchUp();
            await Future<void>.delayed(const Duration(milliseconds: 600));
            await _vaciarColasYSubirPendientes();
            final health = await SyncHealthService.instance.snapshot();
            if (health.dead > 0) {
              syncStatusLabel = 'Sync con errores';
              syncStatusDetail = '${health.dead} ops fallidas en outbox';
            } else if (health.pending > 0 || health.inflight > 0) {
              syncStatusLabel = 'Sincronizando…';
              syncStatusDetail = '${health.pending} pendientes';
            } else {
              syncStatusLabel = 'En la nube';
              syncStatusDetail = null;
            }
            DataRefreshHub.instance.notifyTodo();
          }, tag: 'startCatchupWindows'),
          tag: 'startCatchupWindows',
        );
        return;
      }

      // Primero bajar nube, después subir pendientes (evita pisar datos buenos).
      await _pullInicialCatchUp();
      await _vaciarColasYSubirPendientes();
      _iniciarOutboxPump();

      final health = await SyncHealthService.instance.snapshot();
      if (health.dead > 0) {
        syncStatusLabel = 'Sync con errores';
        syncStatusDetail = '${health.dead} ops fallidas en outbox';
      } else if (health.pending > 0 || health.inflight > 0) {
        syncStatusLabel = 'Sincronizando…';
        syncStatusDetail = '${health.pending} pendientes';
      } else {
        syncStatusLabel = 'En la nube';
        syncStatusDetail = null;
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e, st) {
      syncStatusLabel = 'Local';
      syncStatusDetail = '$e';
      SyncHealthService.instance.recordCycle(
        durationMs: 0,
        error: e.toString(),
      );
      debugPrint('FirestoreSyncService.start falló: $e\n$st');
    }
  }

  /// Sube venta sin tumbar Windows y reintenta outbox si hace falta.
  void programarSubidaVenta(int ventaId) {
    _programarSubidaDocumento(
      tag: 'subirVenta',
      job: () => subirVenta(ventaId),
    );
  }

  /// Sube remito (Ventas totales) con el mismo patrón seguro en Windows.
  void programarSubidaRemito(int remitoId) {
    _programarSubidaDocumento(
      tag: 'subirRemito',
      job: () => subirRemito(remitoId),
    );
  }

  void _programarSubidaDocumento({
    required String tag,
    required Future<void> Function() job,
  }) {
    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await job();
          // Si falló o quedó en cola, drenar un poco ya (no esperar reinicio).
          await _procesarOutboxDrain(maxBatches: 3);
        }, tag: tag),
        tag: tag,
      );
      return;
    }
    syncInBackground(
      () async {
        await job();
        await _procesarOutboxDrain(maxBatches: 2);
      }(),
      tag: tag,
    );
  }

  void _iniciarOutboxPump() {
    _outboxPump?.cancel();
    _outboxPump = Timer.periodic(const Duration(seconds: 40), (_) {
      if (!_puedeEscribirRemoto) return;
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          final pending = await SyncOutbox.instance.countByStatus(
            SyncOutboxStatus.pending,
          );
          if (pending == 0) return;
          syncStatusDetail = '$pending pendientes…';
          await _procesarOutboxDrain(
            maxBatches: PlatformCapabilities.isWindowsDesktop ? 5 : 12,
          );
          final left = await SyncOutbox.instance.countByStatus(
            SyncOutboxStatus.pending,
          );
          if (left == 0) {
            syncStatusLabel = 'En la nube';
            syncStatusDetail = null;
          } else {
            syncStatusLabel = 'Sincronizando…';
            syncStatusDetail = '$left pendientes';
          }
          DataRefreshHub.instance.notifyTodo();
        }, tag: 'outboxPump'),
        tag: 'outboxPump',
      );
    });
  }

  /// Trae de una el estado actual de la nube (clientes/proveedores/…).
  Future<void> _pullInicialCatchUp() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    final windows = PlatformCapabilities.isWindowsDesktop;
    Future<void> pausa() async {
      if (windows) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    try {
      final clientes = await _clientesCol.get();
      await _aplicarClientesRemotos(clientes);
    } catch (e) {
      debugPrint('Pull inicial clientes: $e');
    }
    await pausa();
    try {
      final proveedores = await _proveedoresCol.get();
      await _aplicarProveedoresRemotos(proveedores);
    } catch (e) {
      debugPrint('Pull inicial proveedores: $e');
    }
    await pausa();
    try {
      final productos = await _remote.obtenerTodos(limit: 10000);
      await _aplicarProductosRemotos(productos);
    } catch (e) {
      debugPrint('Pull inicial productos: $e');
    }
    await pausa();
    try {
      final ventas = await _ventasCol.get();
      await _aplicarVentasRemotas(ventas);
    } catch (e) {
      debugPrint('Pull inicial ventas: $e');
    }
    await pausa();
    try {
      final remitos = await _remitosCol.get();
      await _aplicarRemitosRemotos(remitos);
    } catch (e) {
      debugPrint('Pull inicial remitos: $e');
    }
    await pausa();
    try {
      final compras = await _comprasCol.get();
      await _aplicarComprasRemotas(compras);
    } catch (e) {
      debugPrint('Pull inicial compras: $e');
    }
    await pausa();
    try {
      final docs = await _documentosCol.get();
      await _aplicarDocumentosRemotos(docs);
    } catch (e) {
      debugPrint('Pull inicial documentos: $e');
    }
  }

  Future<void> _vaciarColasYSubirPendientes() async {
    final sw = Stopwatch()..start();
    String? cycleError;
    try {
      await _cargarColasPersistidas();
      await SyncOutbox.instance.reclaimStaleInflight();
      await _migrateLegacyColasToOutbox();

      // Volcar colas en memoria → outbox (idempotente). NO borrar hasta ACK.
      for (final id in _colaClientes) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'cliente', localId: id);
      }
      for (final id in _colaProveedores) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'proveedor', localId: id);
      }
      for (final id in _colaProductos) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'producto', localId: id);
      }
      for (final id in _colaVentas) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'venta', localId: id);
      }
      for (final id in _colaRemitos) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'remito', localId: id);
      }
      for (final id in _colaCompras) {
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'compra', localId: id);
      }

      if (!_puedeEscribirRemoto) {
        SyncHealthService.instance.canWrite = false;
        return;
      }
      SyncHealthService.instance.canWrite = true;

      await _procesarOutboxBatch();

      // Config local pendiente (listas / categorías) tras cortes de red.
      if (await _isConfigPendiente(_prefsConfigListasPendiente)) {
        await subirListasPrecios();
      }
      if (await _isConfigPendiente(_prefsConfigCategoriasPendiente)) {
        await subirCategorias();
      }

      // Catch-up: encolar ausentes (sin wipe de cola).
      final db = await DatabaseHelper.instance.database;
      await _subirClientesAusentesEnNube(db);
      await _subirProveedoresAusentesEnNube(db);
      await _subirProductosAusentesEnNube(db);
      await _flushColaStockOps();

      // Capacidad 9: catch-up paginado (sin techo fijo de 2000 recientes).
      final nVentas = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'ventas',
        entityType: 'venta',
      );
      final nRemitos = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'remitos',
        entityType: 'remito',
      );
      final nCompras = await SyncCatchup.instance.enqueueDocumentCatchup(
        db: db,
        table: 'compras',
        entityType: 'compra',
      );
      SyncHealthService.instance.markCollection(
        'catchup',
        'ventas=$nVentas remitos=$nRemitos compras=$nCompras',
      );

      await _procesarOutboxDrain(
        maxBatches: PlatformCapabilities.isWindowsDesktop ? 5 : 25,
      );
      SyncHealthService.instance.markCollection('outbox', 'flushed');
    } catch (e) {
      cycleError = '$e';
      debugPrint('Vaciar colas sync: $e');
      syncStatusDetail = 'Pendiente subir locales: $e';
      SyncHealthService.instance.markCollection('outbox', 'error');
    } finally {
      SyncHealthService.instance.recordCycle(
        durationMs: sw.elapsedMilliseconds,
        error: cycleError,
      );
    }
  }

  Future<void> _procesarOutboxBatch({int limit = 80}) async {
    final batch = await SyncOutbox.instance.claimBatch(limit: limit);
    for (final op in batch) {
      final opId = op['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      try {
        await _ejecutarOutboxOp(op);
        await SyncOutbox.instance.ack(opId);
        SyncHealthService.instance.recordAck();
        _syncMemoryColaTrasAck(op);
      } catch (e) {
        await SyncOutbox.instance.fail(opId, e);
        SyncHealthService.instance.recordFail();
        debugPrint('Outbox fail $opId: $e');
      }
    }
  }

  /// Drena varios batches por ciclo (Capacidad 9).
  Future<void> _procesarOutboxDrain({int maxBatches = 20}) async {
    final windows = PlatformCapabilities.isWindowsDesktop;
    final claimLimit = windows ? 20 : 80;
    for (var i = 0; i < maxBatches; i++) {
      if (windows && i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final before = await SyncOutbox.instance.countByStatus(
        SyncOutboxStatus.pending,
      );
      if (before == 0) {
        final inflight = await SyncOutbox.instance.countByStatus(
          SyncOutboxStatus.inflight,
        );
        if (inflight == 0) break;
      }
      final batch = await SyncOutbox.instance.claimBatch(limit: claimLimit);
      if (batch.isEmpty) break;
      for (final op in batch) {
        final opId = op['op_id']?.toString() ?? '';
        if (opId.isEmpty) continue;
        try {
          await _ejecutarOutboxOp(op);
          await SyncOutbox.instance.ack(opId);
          SyncHealthService.instance.recordAck();
          _syncMemoryColaTrasAck(op);
          if (windows) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
        } catch (e) {
          await SyncOutbox.instance.fail(opId, e);
          SyncHealthService.instance.recordFail();
          debugPrint('Outbox fail $opId: $e');
        }
      }
    }
  }

  void _syncMemoryColaTrasAck(Map<String, dynamic> op) {
    final type = op['entity_type']?.toString() ?? '';
    final localId = (op['entity_local_id'] as num?)?.toInt();
    if (localId == null) return;
    switch (type) {
      case 'cliente':
        _colaClientes.remove(localId);
        unawaited(_persistirCola(_prefsColaClientes, _colaClientes));
      case 'proveedor':
        _colaProveedores.remove(localId);
        unawaited(_persistirCola(_prefsColaProveedores, _colaProveedores));
      case 'producto':
        _colaProductos.remove(localId);
        unawaited(_persistirCola(_prefsColaProductos, _colaProductos));
      case 'venta':
        _colaVentas.remove(localId);
        unawaited(_persistirCola(_prefsColaVentas, _colaVentas));
      case 'remito':
        _colaRemitos.remove(localId);
        unawaited(_persistirCola(_prefsColaRemitos, _colaRemitos));
      case 'compra':
        _colaCompras.remove(localId);
        unawaited(_persistirCola(_prefsColaCompras, _colaCompras));
    }
  }

  Future<void> _ejecutarOutboxOp(Map<String, dynamic> op) async {
    final type = op['entity_type']?.toString() ?? '';
    final operation = op['operation']?.toString() ?? '';
    final localId = (op['entity_local_id'] as num?)?.toInt();
    final remoteId = op['entity_remote_id']?.toString();

    if (operation == 'delete') {
      await _aplicarTombstoneRemoto(type, remoteId ?? '');
      await _borrarLocalTrasTombstone(
        entityType: type,
        localId: localId,
        remoteId: remoteId,
      );
      return;
    }

    if (type == 'stock_op') {
      await _ejecutarStockOpOutbox(op);
      return;
    }

    if (localId == null) {
      throw StateError('Outbox upsert sin entity_local_id ($type)');
    }

    switch (type) {
      case 'cliente':
        await subirCliente(localId, forzar: true, desdeOutbox: true);
      case 'proveedor':
        await subirProveedor(localId, forzar: true, desdeOutbox: true);
      case 'producto':
        await subirProductoPorId(localId, desdeOutbox: true);
      case 'venta':
        await subirVenta(localId, desdeOutbox: true);
      case 'remito':
        await subirRemito(localId, desdeOutbox: true);
      case 'compra':
        await subirCompra(localId, desdeOutbox: true);
      default:
        throw StateError('Outbox entity_type desconocido: $type');
    }
  }

  Future<void> _ejecutarStockOpOutbox(Map<String, dynamic> op) async {
    final payloadRaw = op['payload']?.toString();
    if (payloadRaw == null || payloadRaw.isEmpty) {
      throw StateError('stock_op sin payload');
    }
    final payload = jsonDecode(payloadRaw);
    if (payload is! Map) {
      throw StateError('stock_op payload inválido');
    }
    final map = Map<String, dynamic>.from(payload);
    final opId =
        map['opId']?.toString() ?? op['entity_remote_id']?.toString() ?? '';
    final codigo = map['codigo']?.toString() ?? '';
    final delta = (map['delta'] as num?)?.toInt() ?? 0;
    if (opId.isEmpty || codigo.isEmpty || delta == 0) {
      throw StateError('stock_op incompleto');
    }
    if (_stockOpsHechas.contains(opId)) return;
    await _remote.ajustarStock(codigo: codigo, delta: delta, opId: opId);
    _stockOpsHechas.add(opId);
    await _persistirStockOpsHechas();
  }

  Future<void> _aplicarTombstoneRemoto(String entityType, String remoteId) async {
    if (remoteId.isEmpty) return;
    final uid = FirebaseAuthUsuarioService.instance.uidActual ?? '';
    final opId = 'delete:$entityType:$remoteId';
    final tombstone = buildTombstonePayload(opId: opId, deletedBy: uid);
    switch (entityType) {
      case 'cliente':
        await _clientesCol.doc(remoteId).set(tombstone, SetOptions(merge: true));
      case 'proveedor':
        await _proveedoresCol
            .doc(remoteId)
            .set(tombstone, SetOptions(merge: true));
      case 'venta':
        await _ventasCol.doc(remoteId).set({
          ...tombstone,
          'numero': remoteId,
          'estado': 'anulada',
        }, SetOptions(merge: true));
      case 'remito':
        await _remitosCol.doc(remoteId).set({
          ...tombstone,
          'numero': remoteId,
          'estado': 'anulado',
        }, SetOptions(merge: true));
      case 'compra':
        await _comprasCol.doc(remoteId).set({
          ...tombstone,
          'numero': remoteId,
          'estado': 'anulada',
        }, SetOptions(merge: true));
      default:
        throw StateError('Tombstone no soportado: $entityType');
    }
  }

  /// Si quedó fila local (crash entre enqueue y hard-delete), la limpia tras ACK remoto.
  Future<void> _borrarLocalTrasTombstone({
    required String entityType,
    int? localId,
    String? remoteId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    switch (entityType) {
      case 'cliente':
        if (localId != null) {
          await db.delete('clientes', where: 'id = ?', whereArgs: [localId]);
        } else if (remoteId != null && remoteId.isNotEmpty) {
          await db.delete(
            'clientes',
            where: 'syncId = ?',
            whereArgs: [remoteId],
          );
        }
      case 'proveedor':
        if (localId != null) {
          await db
              .delete('proveedores', where: 'id = ?', whereArgs: [localId]);
        } else if (remoteId != null && remoteId.isNotEmpty) {
          await db.delete(
            'proveedores',
            where: 'syncId = ?',
            whereArgs: [remoteId],
          );
        }
      case 'venta':
        final id = localId ?? await _idPorNumero(db, 'ventas', remoteId);
        if (id != null) {
          await db.delete('pagos', where: 'ventaId = ?', whereArgs: [id]);
          await db
              .delete('ventas_items', where: 'ventaId = ?', whereArgs: [id]);
          await db.delete('ventas', where: 'id = ?', whereArgs: [id]);
        }
      case 'remito':
        final id = localId ?? await _idPorNumero(db, 'remitos', remoteId);
        if (id != null) {
          await db
              .delete('remito_items', where: 'remitoId = ?', whereArgs: [id]);
          await db.delete('remitos', where: 'id = ?', whereArgs: [id]);
        }
        if (remoteId != null && remoteId.isNotEmpty) {
          _remitosConfirmadosEnNube.remove(remoteId);
          await _persistirWatermarkRemitos();
        }
      case 'compra':
        final id = localId ?? await _idPorNumero(db, 'compras', remoteId);
        if (id != null) {
          await db
              .delete('compra_items', where: 'compraId = ?', whereArgs: [id]);
          await db.delete('compras', where: 'id = ?', whereArgs: [id]);
        }
      default:
        break;
    }
  }

  Future<int?> _idPorNumero(
    Database db,
    String table,
    String? numero,
  ) async {
    if (numero == null || numero.isEmpty) return null;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'numero = ?',
      whereArgs: [numero],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num?)?.toInt();
  }

  Future<void> _migrateLegacyColasToOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'sync_outbox_migrated_v1';
    if (prefs.getBool(flag) == true) return;
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'cliente', ids: _colaClientes);
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'proveedor', ids: _colaProveedores);
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'producto', ids: _colaProductos);
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'venta', ids: _colaVentas);
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'remito', ids: _colaRemitos);
    await SyncOutbox.instance
        .migrateLegacyIdSet(entityType: 'compra', ids: _colaCompras);
    await prefs.setBool(flag, true);
  }

  Future<void> _cargarWatermarksPersistidos() async {
    _clientesConfirmadosEnNube
      ..clear()
      ..addAll(await SyncWatermarkStore.instance.loadConfirmed('clientes'));
    _remitosConfirmadosEnNube
      ..clear()
      ..addAll(await SyncWatermarkStore.instance.loadConfirmed('remitos'));
  }

  Future<void> _persistirWatermarkClientes() async {
    await SyncWatermarkStore.instance
        .saveConfirmed('clientes', _clientesConfirmadosEnNube);
  }

  Future<void> _persistirWatermarkRemitos() async {
    await SyncWatermarkStore.instance
        .saveConfirmed('remitos', _remitosConfirmadosEnNube);
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
    _outboxPump?.cancel();
    _outboxPump = null;
    await _productosSub?.cancel();
    await _usuariosSub?.cancel();
    await _brandingSub?.cancel();
    await _permisosSub?.cancel();
    await _listasSub?.cancel();
    await _categoriasSub?.cancel();
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
    _listasSub = null;
    _categoriasSub = null;
    _ventasSub = null;
    _remitosSub = null;
    _clientesSub = null;
    _proveedoresSub = null;
    _comprasSub = null;
    _documentosSub = null;
    _productosSnapshotInicial = true;
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
      final listasSnap = await _configDoc('listas_precios').get();
      if (!listasSnap.exists) {
        await subirListasPrecios();
      }
      final catSnap = await _configDoc('categorias').get();
      if (!catSnap.exists) {
        await subirCategorias();
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

  Future<void> subirListasPrecios() async {
    // Marca durable: si falla/cuelga la red, se reintenta al volver a sincronizar.
    await _setConfigPendiente(_prefsConfigListasPendiente, true);
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('listas_precios', orderBy: 'orden ASC');
      await _configDoc('listas_precios').set({
        'items': rows.map((r) {
          final m = Map<String, dynamic>.from(r)..remove('id');
          if (m['activa'] is bool) {
            m['activa'] = (m['activa'] as bool) ? 1 : 0;
          }
          return m;
        }).toList(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      await _setConfigPendiente(_prefsConfigListasPendiente, false);
    } catch (e) {
      debugPrint('Firestore subir listas: $e');
    }
  }

  Future<void> subirCategorias() async {
    await _setConfigPendiente(_prefsConfigCategoriasPendiente, true);
    if (!_puedeEscribirRemoto) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('categorias', orderBy: 'nombre ASC');
      await _configDoc('categorias').set({
        'items': rows.map((r) {
          final m = Map<String, dynamic>.from(r)..remove('id');
          if (m['activa'] is bool) {
            m['activa'] = (m['activa'] as bool) ? 1 : 0;
          }
          return m;
        }).toList(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      });
      await _setConfigPendiente(_prefsConfigCategoriasPendiente, false);
    } catch (e) {
      debugPrint('Firestore subir categorias: $e');
    }
  }

  bool _sincronizandoListas = false;
  bool _sincronizandoCategorias = false;

  Future<void> _aplicarListasPreciosRemotas(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoListas || !snap.exists) return;
    _sincronizandoListas = true;
    try {
      final raw = snap.data()?['items'];
      if (raw is! List) return;
      final db = await DatabaseHelper.instance.database;
      await db.delete('listas_precios');
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item)..remove('id');
        if (map['activa'] is bool) {
          map['activa'] = (map['activa'] as bool) ? 1 : 0;
        }
        map['porcentaje'] = _asDouble(map['porcentaje']);
        map['orden'] = (map['orden'] as num?)?.toInt() ?? 0;
        map['prioridad'] = (map['prioridad'] as num?)?.toInt() ?? 0;
        map['nombre'] = (map['nombre'] ?? '').toString();
        map['color'] = (map['color'] ?? '').toString();
        await db.insert('listas_precios', map);
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar listas remotas: $e');
    } finally {
      _sincronizandoListas = false;
    }
  }

  Future<void> _aplicarCategoriasRemotas(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoCategorias || !snap.exists) return;
    _sincronizandoCategorias = true;
    try {
      final raw = snap.data()?['items'];
      if (raw is! List) return;
      final db = await DatabaseHelper.instance.database;
      await db.delete('categorias');
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item)..remove('id');
        if (map['activa'] is bool) {
          map['activa'] = (map['activa'] as bool) ? 1 : 0;
        }
        map['activa'] = _asInt01(map['activa']);
        map['nombre'] = (map['nombre'] ?? '').toString();
        map['descripcion'] = (map['descripcion'] ?? '').toString();
        if ((map['nombre'] as String).trim().isEmpty) continue;
        await db.insert('categorias', map);
      }
      DataRefreshHub.instance.notifyTodo();
    } catch (e) {
      debugPrint('Aplicar categorias remotas: $e');
    } finally {
      _sincronizandoCategorias = false;
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
        if (url != null) {
          foto = url;
          u = u.copyWith(foto: foto);
          await _usuariosLocal.actualizar(u);
        } else {
          // Soft-fail: dejamos la foto local en el dispositivo; no bloqueamos sync.
          debugPrint(
            'FirestoreSync foto perfil: '
            '${MediaSyncService.instance.lastError}',
          );
        }
      } else {
        foto = '';
        u = u.copyWith(foto: '');
      }
    }
    // A Firestore: URL remota si hay; si la foto quedó solo local, el repo
    // omite el campo y no borra la foto de la nube.
    await _usuariosRemote.actualizar(u.copyWith(foto: foto));
  }

  Future<void> _aplicarUsuariosRemotos(List<Usuario> remotos) async {
    if (_sincronizandoUsuarios) return;
    _sincronizandoUsuarios = true;
    try {
      for (final remoto in remotos) {
        // Fase 1: password ya no viaja por Firestore.
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

  static const _prefsColaClientes = 'sync_cola_clientes_ids';
  static const _prefsColaProveedores = 'sync_cola_proveedores_ids';
  static const _prefsColaProductos = 'sync_cola_productos_ids';
  static const _prefsColaVentas = 'sync_cola_ventas_ids';
  static const _prefsColaRemitos = 'sync_cola_remitos_ids';
  static const _prefsColaCompras = 'sync_cola_compras_ids';
  static const _prefsColaStockOps = 'sync_cola_stock_ops_v2';
  static const _prefsConfigListasPendiente = 'sync_config_listas_pendiente';
  static const _prefsConfigCategoriasPendiente =
      'sync_config_categorias_pendiente';

  Future<void> _setConfigPendiente(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<bool> _isConfigPendiente(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }
  static const _prefsStockOpsHechas = 'sync_stock_ops_hechas_v2';
  final Set<String> _stockOpsHechas = {};
  bool _productosSnapshotInicial = true;

  static const _colsCliente = {
    'syncId',
    'nombre',
    'apellido',
    'telefono',
    'whatsapp',
    'email',
    'direccion',
    'localidad',
    'provincia',
    'cuit',
    'condicionIva',
    'observaciones',
    'foto',
    'descuento',
    'saldo',
    'limiteCuenta',
    'fechaCreacion',
    'activo',
  };

  static const _colsProveedor = {
    'syncId',
    'nombre',
    'telefono',
    'email',
    'observaciones',
    'fechaCreacion',
    'activo',
    'contacto',
    'cuit',
    'whatsapp',
    'web',
    'condicionesComerciales',
    'tiempoEntrega',
    'actualizadoEn',
  };

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  int _asInt01(dynamic v, {int defaultValue = 1}) {
    if (v == null) return defaultValue;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v != 0 ? 1 : 0;
    final t = v.toString().trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'si') return 1;
    if (t == 'false' || t == '0' || t == 'no') return 0;
    return defaultValue;
  }

  Map<String, dynamic> _sanitizarClienteRemoto(
    Map<String, dynamic> data,
    String syncId,
  ) {
    final out = <String, dynamic>{'syncId': syncId};
    for (final k in _colsCliente) {
      if (k == 'syncId') continue;
      if (!data.containsKey(k)) continue;
      out[k] = data[k];
    }
    // Solo normalizar claves presentes (no inventar ''/0: borraría datos locales).
    for (final k in const [
      'nombre',
      'apellido',
      'telefono',
      'whatsapp',
      'email',
      'direccion',
      'localidad',
      'provincia',
      'cuit',
      'condicionIva',
      'observaciones',
      'fechaCreacion',
    ]) {
      if (out.containsKey(k)) out[k] = (out[k] ?? '').toString();
    }
    if (!out.containsKey('nombre')) {
      out['nombre'] = (data['nombre'] ?? '').toString();
    }
    for (final k in const ['descuento', 'saldo', 'limiteCuenta']) {
      if (out.containsKey(k)) out[k] = _asDouble(out[k]);
    }
    if (out.containsKey('activo')) {
      out['activo'] = _asInt01(out['activo']);
    }
    if (data.containsKey('actualizadoEn')) {
      out['actualizadoEn'] = data['actualizadoEn']?.toString() ?? '';
    }
    // Foto: solo URLs remotas; si falta o es path local, no tocar la local.
    if (out.containsKey('foto')) {
      final foto = out['foto']?.toString() ?? '';
      if (foto.startsWith('http://') || foto.startsWith('https://')) {
        out['foto'] = foto;
      } else {
        out.remove('foto');
      }
    }
    return out;
  }

  Map<String, dynamic> _sanitizarProveedorRemoto(
    Map<String, dynamic> data,
    String syncId,
  ) {
    final out = <String, dynamic>{'syncId': syncId};
    for (final k in _colsProveedor) {
      if (k == 'syncId') continue;
      if (!data.containsKey(k)) continue;
      out[k] = data[k];
    }
    out['nombre'] = (out['nombre'] ?? '').toString();
    out['telefono'] = (out['telefono'] ?? '').toString();
    out['email'] = (out['email'] ?? '').toString();
    out['observaciones'] = (out['observaciones'] ?? '').toString();
    out['contacto'] = (out['contacto'] ?? '').toString();
    out['cuit'] = (out['cuit'] ?? '').toString();
    out['whatsapp'] = (out['whatsapp'] ?? '').toString();
    out['web'] = (out['web'] ?? '').toString();
    out['condicionesComerciales'] =
        (out['condicionesComerciales'] ?? '').toString();
    out['tiempoEntrega'] = (out['tiempoEntrega'] ?? '').toString();
    out['activo'] = _asInt01(out['activo'], defaultValue: 1);
    if (data.containsKey('actualizadoEn')) {
      out['actualizadoEn'] = data['actualizadoEn']?.toString() ?? '';
    }
    return out;
  }

  Future<void> _persistirCola(String key, Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        key,
        ids.map((e) => e.toString()).toList(),
      );
    } catch (_) {}
  }

  Future<void> _cargarColasPersistidas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final s in prefs.getStringList(_prefsColaClientes) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaClientes.add(id);
      }
      for (final s in prefs.getStringList(_prefsColaProveedores) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaProveedores.add(id);
      }
      for (final s in prefs.getStringList(_prefsColaProductos) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaProductos.add(id);
      }
      for (final s in prefs.getStringList(_prefsColaVentas) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaVentas.add(id);
      }
      for (final s in prefs.getStringList(_prefsColaRemitos) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaRemitos.add(id);
      }
      for (final s in prefs.getStringList(_prefsColaCompras) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) _colaCompras.add(id);
      }
      _colaStockOps
        ..clear()
        ..addAll(prefs.getStringList(_prefsColaStockOps) ?? const []);
      _stockOpsHechas
        ..clear()
        ..addAll(prefs.getStringList(_prefsStockOpsHechas) ?? const []);
    } catch (_) {}
  }

  Future<void> _persistirColaStockOps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsColaStockOps, List<String>.from(_colaStockOps));
    } catch (_) {}
  }

  Future<void> _persistirStockOpsHechas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Conservar las últimas N para no crecer sin límite.
      final list = _stockOpsHechas.toList();
      final trimmed = list.length > 500 ? list.sublist(list.length - 500) : list;
      _stockOpsHechas
        ..clear()
        ..addAll(trimmed);
      await prefs.setStringList(_prefsStockOpsHechas, trimmed);
    } catch (_) {}
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

  DateTime? _parseUtc(dynamic raw) {
    if (raw == null) return null;
    final t = raw.toString().trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t)?.toUtc();
  }

  Future<void> _subirClientesAusentesEnNube(Database db) async {
    try {
      final remote = await _clientesCol.get();
      final remoteIds = <String>{};
      for (final d in remote.docs) {
        remoteIds.add(d.id);
        final sid = d.data()['syncId']?.toString();
        if (sid != null && sid.isNotEmpty) remoteIds.add(sid);
      }
      final locales = await db.query(
        'clientes',
        columns: ['id', 'syncId', 'activo'],
      );
      for (final row in locales) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        if (_asInt01(row['activo'], defaultValue: 1) == 0) continue;
        var syncId = row['syncId']?.toString() ?? '';
        if (syncId.isEmpty) {
          syncId = await asegurarSyncIdCliente(id);
        }
        if (syncId.isEmpty) continue;
        if (!remoteIds.contains(syncId)) {
          await subirCliente(id, forzar: true);
        }
      }
    } catch (e) {
      debugPrint('Subir clientes ausentes: $e');
    }
  }

  Future<void> _subirProveedoresAusentesEnNube(Database db) async {
    try {
      final remote = await _proveedoresCol.get();
      final remoteIds = <String>{};
      for (final d in remote.docs) {
        remoteIds.add(d.id);
        final sid = d.data()['syncId']?.toString();
        if (sid != null && sid.isNotEmpty) remoteIds.add(sid);
      }
      final locales = await db.query(
        'proveedores',
        columns: ['id', 'syncId', 'activo'],
      );
      for (final row in locales) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        if (_asInt01(row['activo'], defaultValue: 1) == 0) continue;
        var syncId = row['syncId']?.toString() ?? '';
        if (syncId.isEmpty) {
          syncId = await asegurarSyncIdProveedor(id);
        }
        if (syncId.isEmpty) continue;
        if (!remoteIds.contains(syncId)) {
          await subirProveedor(id, forzar: true);
        }
      }
    } catch (e) {
      debugPrint('Subir proveedores ausentes: $e');
    }
  }

  /// Solo productos que aún no tienen doc en la nube (incluye papelera local).
  Future<void> _subirProductosAusentesEnNube(Database db) async {
    try {
      // Capacidad 9: recorrer remoto por páginas (sin techo 10k oculto).
      final remoteCodigos = <String>{};
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      const pageSize = 500;
      while (true) {
        Query<Map<String, dynamic>> q =
            _col('productos').orderBy(FieldPath.documentId).limit(pageSize);
        if (cursor != null) {
          q = q.startAfterDocument(cursor);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final d in snap.docs) {
          final codigo = d.data()['codigo']?.toString().trim() ?? d.id.trim();
          if (codigo.isNotEmpty) remoteCodigos.add(codigo);
        }
        cursor = snap.docs.last;
        if (snap.docs.length < pageSize) break;
      }

      final locales = await db.query('productos', columns: ['id', 'codigo']);
      final windows = PlatformCapabilities.isWindowsDesktop;
      var subidos = 0;
      for (final row in locales) {
        final id = (row['id'] as num?)?.toInt();
        final codigo = row['codigo']?.toString().trim() ?? '';
        if (id == null || codigo.isEmpty) continue;
        if (!remoteCodigos.contains(codigo)) {
          await subirProductoPorId(id, incluirStockAbsoluto: true, forzar: true);
          subidos += 1;
          if (windows) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            // No saturar el primer ciclo: el resto sale en catch-ups siguientes.
            if (subidos >= 40) break;
          }
        }
      }
    } catch (e) {
      debugPrint('Subir productos ausentes: $e');
    }
  }

  /// Ajusta stock en la nube de forma atómica e idempotente (Fase 2).
  ///
  /// [flushImmediately]: en Windows conviene `false` tras compras/remitos
  /// para no tumbar el .exe con ráfagas Firebase.
  Future<void> ajustarStockEnNube({
    required int productoId,
    required int delta,
    String? opId,
    bool flushImmediately = true,
  }) async {
    if (delta == 0) return;
    final idOp = (opId == null || opId.isEmpty) ? const Uuid().v4() : opId;
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'productos',
      columns: ['codigo'],
      where: 'id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final codigo = rows.first['codigo']?.toString().trim() ?? '';
    if (codigo.isEmpty) return;

    final token = '$idOp|$codigo|$delta';
    // Capacidad 7: stock ops viven en outbox SQLite (no solo prefs).
    await SyncOutbox.instance.enqueueStockOp(
      opId: idOp,
      codigo: codigo,
      delta: delta,
    );
    if (!_colaStockOps.contains(token)) {
      _colaStockOps.add(token);
      await _persistirColaStockOps();
    }
    if (flushImmediately) {
      await _flushColaStockOps();
    }
  }

  /// Expone flush diferido (Windows: tras compras, sin tumbar el .exe).
  Future<void> flushStockOpsPendientes() => _flushColaStockOps();

  Future<void> _flushColaStockOps() async {
    // Migrar tokens legacy prefs → outbox (idempotente).
    for (final token in List<String>.from(_colaStockOps)) {
      final parts = token.split('|');
      if (parts.length < 3) {
        _colaStockOps.remove(token);
        continue;
      }
      final opId = parts[0];
      final codigo = parts[1];
      final delta = int.tryParse(parts[2]) ?? 0;
      if (opId.isEmpty || codigo.isEmpty || delta == 0) {
        _colaStockOps.remove(token);
        continue;
      }
      await SyncOutbox.instance.enqueueStockOp(
        opId: opId,
        codigo: codigo,
        delta: delta,
      );
      _colaStockOps.remove(token);
    }
    await _persistirColaStockOps();

    if (!_puedeEscribirRemoto) return;
    try {
      await _procesarOutboxBatch(limit: 40);
      await _remote.reconcilizarStockOpsPendientes(limit: 30);
    } catch (e) {
      debugPrint('Flush stock ops: $e');
    }
  }

  void _onProductosSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    try {
      final List<Producto> lote;
      if (_productosSnapshotInicial || snap.docChanges.isEmpty) {
        _productosSnapshotInicial = false;
        lote = snap.docs
            .map((d) => Producto.fromFirestore(d.data(), docId: d.id))
            .toList();
      } else {
        lote = snap.docChanges
            .where((c) => c.type != DocumentChangeType.removed)
            .map((c) {
              final data = c.doc.data();
              if (data == null) return null;
              return Producto.fromFirestore(data, docId: c.doc.id);
            })
            .whereType<Producto>()
            .toList();
      }
      if (lote.isEmpty) return;
      // Windows: el snapshot inicial (miles de productos) no debe pelear
      // con el resto del arranque de sync en el mismo instante.
      if (PlatformCapabilities.isWindowsDesktop) {
        syncInBackground(
          CloudSyncThrottle.enqueue(
            () => _aplicarProductosRemotos(lote),
            tag: 'productosSnapshot',
          ),
          tag: 'productosSnapshot',
        );
        return;
      }
      unawaited(_aplicarProductosRemotos(lote));
    } catch (e) {
      debugPrint('onProductosSnapshot: $e');
    }
  }

  Future<void> subirCliente(
    int clienteId, {
    bool forzar = false,
    bool desdeOutbox = false,
  }) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'cliente', localId: clienteId);
    }
    if (!_puedeEscribirRemoto) {
      _colaClientes.add(clienteId);
      unawaited(_persistirCola(_prefsColaClientes, _colaClientes));
      syncStatusDetail =
          'Cliente guardado acá. Falta sesión de nube para enviarlo a la PC.';
      debugPrint('subirCliente: sin sesión, en cola id=$clienteId');
      return;
    }
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
      final payload = {
        ...cliente.toFirestore(),
        'localId': clienteId,
        'activo': _asInt01(rows.first['activo'], defaultValue: 1),
      };
      // Last-write-wins: no pisar un remoto más nuevo (salvo edición forzada).
      if (!forzar) {
        final remoto = await _clientesCol.doc(syncId).get();
        if (remoto.exists) {
          final remTs = _parseUtc(remoto.data()?['actualizadoEn']);
          final locTs = _parseUtc(
            rows.first['actualizadoEn'] ?? payload['actualizadoEn'],
          );
          if (remTs != null && locTs != null && remTs.isAfter(locTs)) {
            debugPrint(
              'subirCliente: remoto más nuevo, skip id=$clienteId sync=$syncId',
            );
            await SyncWatermarkStore.instance.recordConflict(
              entityType: 'cliente',
              entityId: syncId,
              localRevision: locTs.toIso8601String(),
              remoteRevision: remTs.toIso8601String(),
              resolution: 'remote_wins',
              detail: 'LWW skip upload',
            );
            if (!desdeOutbox) {
              await SyncOutbox.instance.ack('upsert:cliente:$clienteId');
            }
            _colaClientes.remove(clienteId);
            unawaited(_persistirCola(_prefsColaClientes, _colaClientes));
            return;
          }
        }
      }
      await _clientesCol.doc(syncId).set(payload, SetOptions(merge: true));
      await db.update(
        'clientes',
        {'actualizadoEn': payload['actualizadoEn']},
        where: 'id = ?',
        whereArgs: [clienteId],
      );
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:cliente:$clienteId');
      }
      _colaClientes.remove(clienteId);
      unawaited(_persistirCola(_prefsColaClientes, _colaClientes));
    } catch (e) {
      _colaClientes.add(clienteId);
      unawaited(_persistirCola(_prefsColaClientes, _colaClientes));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:cliente:$clienteId', e);
      }
      syncStatusDetail = 'No se pudo subir cliente: $e';
      debugPrint('Firestore subir cliente: $e');
      if (desdeOutbox) rethrow;
    }
  }

  Future<void> eliminarClienteRemoto(String syncId, {int? localId}) async {
    if (syncId.isEmpty) return;
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'cliente',
      remoteId: syncId,
      localId: localId,
    );
    if (!_puedeEscribirRemoto) return;
    try {
      await _aplicarTombstoneRemoto('cliente', syncId);
      await _borrarLocalTrasTombstone(
        entityType: 'cliente',
        localId: localId,
        remoteId: syncId,
      );
      await SyncOutbox.instance.ack('delete:cliente:$syncId');
    } catch (e) {
      await SyncOutbox.instance.fail('delete:cliente:$syncId', e);
      debugPrint('Firestore eliminar cliente: $e');
    }
  }

  Future<void> subirProveedor(
    int proveedorId, {
    bool forzar = false,
    bool desdeOutbox = false,
  }) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'proveedor', localId: proveedorId);
    }
    if (!_puedeEscribirRemoto) {
      _colaProveedores.add(proveedorId);
      unawaited(_persistirCola(_prefsColaProveedores, _colaProveedores));
      syncStatusDetail =
          'Proveedor guardado acá. Falta sesión de nube para enviarlo.';
      debugPrint('subirProveedor: sin sesión, en cola id=$proveedorId');
      return;
    }
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
      var proveedor = Proveedor.fromMap(rows.first);
      if (proveedor.actualizadoEn == null ||
          proveedor.actualizadoEn!.isEmpty) {
        final ahora = DateTime.now().toUtc().toIso8601String();
        proveedor = proveedor.copyWith(actualizadoEn: ahora);
        await db.update(
          'proveedores',
          {'actualizadoEn': ahora},
          where: 'id = ?',
          whereArgs: [proveedorId],
        );
      }
      final payload = {
        ...proveedor.toFirestore(),
        'localId': proveedorId,
      };
      if (!forzar) {
        final remoto = await _proveedoresCol.doc(syncId).get();
        if (remoto.exists) {
          final remTs = _parseUtc(remoto.data()?['actualizadoEn']);
          final locTs = _parseUtc(payload['actualizadoEn']);
          if (remTs != null && locTs != null && remTs.isAfter(locTs)) {
            debugPrint(
              'subirProveedor: remoto más nuevo, skip id=$proveedorId',
            );
            await SyncWatermarkStore.instance.recordConflict(
              entityType: 'proveedor',
              entityId: syncId,
              localRevision: locTs.toIso8601String(),
              remoteRevision: remTs.toIso8601String(),
              resolution: 'remote_wins',
              detail: 'LWW skip upload',
            );
            if (!desdeOutbox) {
              await SyncOutbox.instance.ack('upsert:proveedor:$proveedorId');
            }
            _colaProveedores.remove(proveedorId);
            unawaited(_persistirCola(_prefsColaProveedores, _colaProveedores));
            return;
          }
        }
      }
      await _proveedoresCol.doc(syncId).set(payload, SetOptions(merge: true));
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:proveedor:$proveedorId');
      }
      _colaProveedores.remove(proveedorId);
      unawaited(_persistirCola(_prefsColaProveedores, _colaProveedores));
    } catch (e) {
      _colaProveedores.add(proveedorId);
      unawaited(_persistirCola(_prefsColaProveedores, _colaProveedores));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:proveedor:$proveedorId', e);
      }
      syncStatusDetail = 'No se pudo subir proveedor: $e';
      debugPrint('Firestore subir proveedor: $e');
      if (desdeOutbox) rethrow;
    }
  }

  Future<void> eliminarProveedorRemoto(String syncId, {int? localId}) async {
    if (syncId.isEmpty) return;
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'proveedor',
      remoteId: syncId,
      localId: localId,
    );
    if (!_puedeEscribirRemoto) return;
    try {
      await _aplicarTombstoneRemoto('proveedor', syncId);
      await _borrarLocalTrasTombstone(
        entityType: 'proveedor',
        localId: localId,
        remoteId: syncId,
      );
      await SyncOutbox.instance.ack('delete:proveedor:$syncId');
    } catch (e) {
      await SyncOutbox.instance.fail('delete:proveedor:$syncId', e);
      debugPrint('Firestore eliminar proveedor: $e');
    }
  }

  Future<void> subirCompra(int compraId, {bool desdeOutbox = false}) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'compra', localId: compraId);
    }
    if (!_puedeEscribirRemoto) {
      _colaCompras.add(compraId);
      unawaited(_persistirCola(_prefsColaCompras, _colaCompras));
      syncStatusDetail =
          'Compra guardada acá. Falta sesión de nube para enviarla.';
      if (desdeOutbox) {
        throw StateError('Sin sesión de nube para subir compra $compraId');
      }
      return;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'compras',
        where: 'id = ?',
        whereArgs: [compraId],
        limit: 1,
      );
      if (rows.isEmpty) {
        if (desdeOutbox) {
          throw StateError('Compra local $compraId no existe');
        }
        return;
      }
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
        final pidRaw = item['productoId'];
        final pid = pidRaw is int
            ? pidRaw
            : (pidRaw is num ? pidRaw.toInt() : null);
        if (pid == null) continue;
        // Siempre encolar; en Windows no subir ya (evita crash del .exe).
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'producto', localId: pid);
        if (!PlatformCapabilities.isWindowsDesktop) {
          await subirProductoPorId(pid);
        }
      }
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:compra:$compraId');
      }
      _colaCompras.remove(compraId);
      unawaited(_persistirCola(_prefsColaCompras, _colaCompras));
    } catch (e) {
      _colaCompras.add(compraId);
      unawaited(_persistirCola(_prefsColaCompras, _colaCompras));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:compra:$compraId', e);
      }
      debugPrint('Firestore subir compra: $e');
      if (desdeOutbox) rethrow;
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

  Future<void> subirVenta(int ventaId, {bool desdeOutbox = false}) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'venta', localId: ventaId);
    }
    if (!_puedeEscribirRemoto) {
      _colaVentas.add(ventaId);
      unawaited(_persistirCola(_prefsColaVentas, _colaVentas));
      syncStatusDetail =
          'Venta guardada acá. Falta sesión de nube para enviarla.';
      if (desdeOutbox) {
        throw StateError('Sin sesión de nube para subir venta $ventaId');
      }
      return;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT v.*, c.nombre AS clienteNombre, c.syncId AS clienteSyncId,
               c.cuit AS clienteCuit
        FROM ventas v
        LEFT JOIN clientes c ON c.id = v.clienteId
        WHERE v.id = ?
      ''', [ventaId]);
      if (rows.isEmpty) {
        if (desdeOutbox) {
          throw StateError('Venta local $ventaId no existe');
        }
        return;
      }
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
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:venta:$ventaId');
      }
      _colaVentas.remove(ventaId);
      unawaited(_persistirCola(_prefsColaVentas, _colaVentas));
    } catch (e) {
      _colaVentas.add(ventaId);
      unawaited(_persistirCola(_prefsColaVentas, _colaVentas));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:venta:$ventaId', e);
      }
      debugPrint('Firestore subir venta: $e');
      if (desdeOutbox) rethrow;
    }
  }

  Future<void> eliminarCompraRemota(String numero, {int? localId}) async {
    if (numero.isEmpty) return;
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'compra',
      remoteId: numero,
      localId: localId,
    );
    if (!_puedeEscribirRemoto) return;
    try {
      await _aplicarTombstoneRemoto('compra', numero);
      await _borrarLocalTrasTombstone(
        entityType: 'compra',
        localId: localId,
        remoteId: numero,
      );
      await SyncOutbox.instance.ack('delete:compra:$numero');
    } catch (e) {
      await SyncOutbox.instance.fail('delete:compra:$numero', e);
      debugPrint('Firestore eliminar compra: $e');
    }
  }

  Future<void> eliminarVentaRemota(Venta venta) async {
    final docId = venta.numero.isNotEmpty ? venta.numero : 'v_${venta.id}';
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'venta',
      remoteId: docId,
      localId: venta.id,
    );
    if (!_puedeEscribirRemoto) return;
    try {
      await _aplicarTombstoneRemoto('venta', docId);
      await _borrarLocalTrasTombstone(
        entityType: 'venta',
        localId: venta.id,
        remoteId: docId,
      );
      await SyncOutbox.instance.ack('delete:venta:$docId');
    } catch (e) {
      await SyncOutbox.instance.fail('delete:venta:$docId', e);
      debugPrint('Firestore eliminar venta: $e');
    }
  }

  Future<void> eliminarRemitoRemoto(String numero, {int? localId}) async {
    if (numero.isEmpty) return;
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'remito',
      remoteId: numero,
      localId: localId,
    );
    if (!_puedeEscribirRemoto) return;

    Future<void> aplicar() async {
      try {
        await _aplicarTombstoneRemoto('remito', numero);
        await _borrarLocalTrasTombstone(
          entityType: 'remito',
          localId: localId,
          remoteId: numero,
        );
        await SyncOutbox.instance.ack('delete:remito:$numero');
      } catch (e) {
        await SyncOutbox.instance.fail('delete:remito:$numero', e);
        debugPrint('Firestore eliminar remito: $e');
      }
    }

    // Windows: no await Firestore en el hilo de UI (cerraba el .exe).
    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(aplicar, tag: 'eliminarRemitoRemoto'),
        tag: 'eliminarRemitoRemoto',
      );
      return;
    }
    await aplicar();
  }

  /// Sube remito + ítems y empuja el stock actualizado de cada producto.
  Future<void> subirRemito(int remitoId, {bool desdeOutbox = false}) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'remito', localId: remitoId);
    }
    if (!_puedeEscribirRemoto) {
      _colaRemitos.add(remitoId);
      unawaited(_persistirCola(_prefsColaRemitos, _colaRemitos));
      syncStatusDetail =
          'Remito guardado acá. Falta sesión de nube para enviarlo.';
      if (desdeOutbox) {
        throw StateError('Sin sesión de nube para subir remito $remitoId');
      }
      return;
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT r.*, c.nombre AS clienteNombre, c.syncId AS clienteSyncId,
               c.cuit AS clienteCuit
        FROM remitos r
        LEFT JOIN clientes c ON c.id = r.clienteId
        WHERE r.id = ?
      ''', [remitoId]);
      if (rows.isEmpty) {
        if (desdeOutbox) {
          throw StateError('Remito local $remitoId no existe');
        }
        return;
      }
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
        ...Map<String, dynamic>.from(remito)..remove('id'),
        'localId': remitoId,
        'clienteNombre': remito['clienteNombre'],
        'clienteSyncId': remito['clienteSyncId'],
        'clienteCuit': remito['clienteCuit'],
        'items': items,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      for (final item in items) {
        final pid = (item['productoId'] as num?)?.toInt();
        if (pid == null) continue;
        // En Windows no subir productos ya (evita tumbar el .exe / fallar el remito).
        await SyncOutbox.instance
            .enqueueUpsert(entityType: 'producto', localId: pid);
        if (!PlatformCapabilities.isWindowsDesktop) {
          await subirProductoPorId(pid);
        }
      }
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:remito:$remitoId');
      }
      _colaRemitos.remove(remitoId);
      unawaited(_persistirCola(_prefsColaRemitos, _colaRemitos));
    } catch (e) {
      _colaRemitos.add(remitoId);
      unawaited(_persistirCola(_prefsColaRemitos, _colaRemitos));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:remito:$remitoId', e);
      }
      debugPrint('Firestore subir remito: $e');
      if (desdeOutbox) rethrow;
    }
  }

  Future<void> subirProductoPorId(
    int productoId, {
    bool incluirStockAbsoluto = false,
    bool forzar = false,
    bool desdeOutbox = false,
  }) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance
          .enqueueUpsert(entityType: 'producto', localId: productoId);
    }
    if (!_puedeEscribirRemoto) {
      _colaProductos.add(productoId);
      unawaited(_persistirCola(_prefsColaProductos, _colaProductos));
      return;
    }
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
      final ahora = DateTime.now().toUtc().toIso8601String();
      if (producto.actualizadoEn == null || producto.actualizadoEn!.isEmpty) {
        producto = producto.copyWith(actualizadoEn: ahora);
        await db.update(
          'productos',
          {'actualizadoEn': ahora},
          where: 'id = ?',
          whereArgs: [productoId],
        );
      }

      // Subir fotos locales a Storage antes de empujar a Firestore
      // (evita sincronizar rutas C:\... o /data/... al otro dispositivo).
      final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
        producto.codigo,
        producto.todasLasFotos,
      );
      if (fotos.isNotEmpty &&
          (fotos.first != producto.fotoPrincipal ||
              fotos.length != producto.todasLasFotos.length)) {
        producto = producto.copyWith(
          foto: fotos.first,
          fotos: fotos,
          actualizadoEn: ahora,
        );
        await db.update(
          'productos',
          {
            'foto': producto.fotoPrincipal,
            'fotos': producto.toMap()['fotos'],
            'actualizadoEn': ahora,
          },
          where: 'id = ?',
          whereArgs: [productoId],
        );
      }

      if (!forzar) {
        try {
          final remoto = await _remote.buscarPorCodigo(producto.codigo);
          if (remoto != null) {
            final remTs = _parseUtc(remoto.actualizadoEn);
            final locTs = _parseUtc(producto.actualizadoEn);
            if (remTs != null &&
                locTs != null &&
                remTs.isAfter(locTs) &&
                !incluirStockAbsoluto) {
              // Remoto más nuevo: no pisar metadata (stock va por deltas).
              await SyncWatermarkStore.instance.recordConflict(
                entityType: 'producto',
                entityId: producto.codigo,
                localRevision: locTs.toIso8601String(),
                remoteRevision: remTs.toIso8601String(),
                resolution: 'remote_wins',
                detail: 'LWW skip upload',
              );
              if (!desdeOutbox) {
                await SyncOutbox.instance.ack('upsert:producto:$productoId');
              }
              _colaProductos.remove(productoId);
              unawaited(_persistirCola(_prefsColaProductos, _colaProductos));
              return;
            }
          }
        } catch (_) {}
      }

      if (incluirStockAbsoluto) {
        await _remote.actualizar(producto);
      } else {
        await _remote.actualizarSinStock(producto);
      }
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:producto:$productoId');
      }
      _colaProductos.remove(productoId);
      unawaited(_persistirCola(_prefsColaProductos, _colaProductos));
    } catch (e) {
      _colaProductos.add(productoId);
      unawaited(_persistirCola(_prefsColaProductos, _colaProductos));
      if (!desdeOutbox) {
        await SyncOutbox.instance.fail('upsert:producto:$productoId', e);
      }
      debugPrint('Firestore subir producto $productoId: $e');
      if (desdeOutbox) rethrow;
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
    if (_sincronizandoClientes) {
      _snapClientesPendiente = snap;
      return;
    }
    _sincronizandoClientes = true;
    try {
      var actual = snap;
      var hubo = false;
      while (true) {
        final db = await DatabaseHelper.instance.database;
        final remoteSyncIds = <String>{};
        for (final doc in actual.docs) {
          try {
            final data = doc.data();
            final syncId = data['syncId']?.toString().isNotEmpty == true
                ? data['syncId'].toString()
                : doc.id;
            final isTombstone = isRemoteTombstone(data);
            if (isTombstone) {
              final existentes = await db.query(
                'clientes',
                columns: ['id'],
                where: 'syncId = ?',
                whereArgs: [syncId],
                limit: 1,
              );
              if (existentes.isNotEmpty) {
                final id = (existentes.first['id'] as num?)?.toInt();
                if (id != null &&
                    !_colaClientes.contains(id) &&
                    !await SyncOutbox.instance
                        .hasPendingLocalId('cliente', id)) {
                  await db.delete('clientes', where: 'id = ?', whereArgs: [id]);
                }
              }
              _clientesConfirmadosEnNube.remove(syncId);
              continue;
            }
            remoteSyncIds.add(syncId);
            final map = _sanitizarClienteRemoto(data, syncId);
            if ((map['nombre'] as String?)?.trim().isEmpty ?? true) continue;

            // Separar metadata de columnas SQLite.
            final actualizadoEn = map.remove('actualizadoEn')?.toString();
            final sqliteMap = Map<String, dynamic>.from(map);
            if (actualizadoEn != null && actualizadoEn.isNotEmpty) {
              sqliteMap['actualizadoEn'] = actualizadoEn;
            }

            final existentes = await db.query(
              'clientes',
              where: 'syncId = ?',
              whereArgs: [syncId],
              limit: 1,
            );
            if (existentes.isEmpty) {
              // Solo unir por CUIT si el local todavía no tiene syncId propio.
              final cuit = sqliteMap['cuit']?.toString() ?? '';
              final porCuit = cuit.isNotEmpty
                  ? await db.query(
                      'clientes',
                      where:
                          'cuit = ? AND (syncId IS NULL OR syncId = "")',
                      whereArgs: [cuit],
                      limit: 1,
                    )
                  : <Map<String, dynamic>>[];
              if (porCuit.isNotEmpty) {
                await db.update(
                  'clientes',
                  sqliteMap,
                  where: 'id = ?',
                  whereArgs: [porCuit.first['id']],
                );
              } else {
                await db.insert('clientes', sqliteMap);
              }
            } else {
              final local = existentes.first;
              final locTs = _parseUtc(local['actualizadoEn']);
              final remTs = _parseUtc(actualizadoEn);
              // Si lo local es más nuevo, no pisar (la edición local manda).
              if (locTs != null && remTs != null && locTs.isAfter(remTs)) {
                continue;
              }
              await db.update(
                'clientes',
                sqliteMap,
                where: 'id = ?',
                whereArgs: [local['id']],
              );
            }
            hubo = true;
          } catch (e) {
            debugPrint('Cliente remoto ${doc.id}: $e');
          }
        }

        // Capacidad 7: solo tombstones borran locales (no inferir por ausencia).
        _clientesConfirmadosEnNube.addAll(remoteSyncIds);
        await _persistirWatermarkClientes();

        if (hubo) DataRefreshHub.instance.notifyTodo();
        final pendiente = _snapClientesPendiente;
        _snapClientesPendiente = null;
        if (pendiente == null) break;
        actual = pendiente;
      }
    } catch (e) {
      debugPrint('Aplicar clientes remotos: $e');
    } finally {
      _sincronizandoClientes = false;
    }
  }

  Future<void> _aplicarProveedoresRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoProveedores) {
      _snapProveedoresPendiente = snap;
      return;
    }
    _sincronizandoProveedores = true;
    try {
      var actual = snap;
      var hubo = false;
      while (true) {
        final db = await DatabaseHelper.instance.database;
        for (final doc in actual.docs) {
          try {
            final data = doc.data();
            final syncId = data['syncId']?.toString().isNotEmpty == true
                ? data['syncId'].toString()
                : doc.id;
            if (isRemoteTombstone(data)) {
              final existentes = await db.query(
                'proveedores',
                columns: ['id'],
                where: 'syncId = ?',
                whereArgs: [syncId],
                limit: 1,
              );
              if (existentes.isNotEmpty) {
                final id = (existentes.first['id'] as num?)?.toInt();
                if (id != null &&
                    !_colaProveedores.contains(id) &&
                    !await SyncOutbox.instance
                        .hasPendingLocalId('proveedor', id)) {
                  await db.delete(
                    'proveedores',
                    where: 'id = ?',
                    whereArgs: [id],
                  );
                  hubo = true;
                }
              }
              continue;
            }
            final map = _sanitizarProveedorRemoto(data, syncId);
            if ((map['nombre'] as String?)?.trim().isEmpty ?? true) continue;

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
                await db.insert('proveedores', map);
              }
            } else {
              final local = existentes.first;
              final locTs = _parseUtc(local['actualizadoEn']);
              final remTs = _parseUtc(map['actualizadoEn']);
              if (locTs != null && remTs != null && locTs.isAfter(remTs)) {
                continue;
              }
              await db.update(
                'proveedores',
                map,
                where: 'id = ?',
                whereArgs: [local['id']],
              );
            }
            hubo = true;
          } catch (e) {
            debugPrint('Proveedor remoto ${doc.id}: $e');
          }
        }
        if (hubo) DataRefreshHub.instance.notifyTodo();
        final pendiente = _snapProveedoresPendiente;
        _snapProveedoresPendiente = null;
        if (pendiente == null) break;
        actual = pendiente;
      }
    } catch (e) {
      debugPrint('Aplicar proveedores remotos: $e');
    } finally {
      _sincronizandoProveedores = false;
    }
  }

  Future<void> _aplicarComprasRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoCompras) {
      _snapComprasPendiente = snap;
      return;
    }
    _sincronizandoCompras = true;
    try {
      var actual = snap;
      while (true) {
      final db = await DatabaseHelper.instance.database;
      for (final doc in actual.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        if (isRemoteTombstone(data)) {
          final existentes = await db.query(
            'compras',
            columns: ['id'],
            where: 'numero = ?',
            whereArgs: [numero],
            limit: 1,
          );
          if (existentes.isNotEmpty) {
            final id = (existentes.first['id'] as num?)?.toInt();
            if (id != null &&
                !_colaCompras.contains(id) &&
                !await SyncOutbox.instance.hasPendingLocalId('compra', id)) {
              await db.delete(
                'compra_items',
                where: 'compraId = ?',
                whereArgs: [id],
              );
              await db.delete('compras', where: 'id = ?', whereArgs: [id]);
            }
          }
          continue;
        }
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
      final pendiente = _snapComprasPendiente;
      _snapComprasPendiente = null;
      if (pendiente == null) break;
      actual = pendiente;
      }
    } catch (e) {
      debugPrint('Aplicar compras remotas: $e');
    } finally {
      _sincronizandoCompras = false;
    }
  }

  Future<void> _aplicarDocumentosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoDocumentos) {
      _snapDocumentosPendiente = snap;
      return;
    }
    _sincronizandoDocumentos = true;
    try {
      var actual = snap;
      while (true) {
      final db = await DatabaseHelper.instance.database;
      for (final doc in actual.docs) {
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
      final pendiente = _snapDocumentosPendiente;
      _snapDocumentosPendiente = null;
      if (pendiente == null) break;
      actual = pendiente;
      }
    } catch (e) {
      debugPrint('Aplicar documentos remotos: $e');
    } finally {
      _sincronizandoDocumentos = false;
    }
  }

  Future<void> _aplicarRemitosRemotos(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoRemitos) {
      _snapRemitosPendiente = snap;
      return;
    }
    _sincronizandoRemitos = true;
    try {
      var actual = snap;
      while (true) {
      final db = await DatabaseHelper.instance.database;
      final remoteNumeros = <String>{};
      var hubo = false;
      for (final doc in actual.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        if (isRemoteTombstone(data)) {
          // Tombstone remoto → borrar local (si no hay upsert pendiente).
          final rows = await db.query(
            'remitos',
            columns: ['id'],
            where: 'numero = ?',
            whereArgs: [numero],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final id = (rows.first['id'] as num?)?.toInt();
            if (id != null &&
                !_colaRemitos.contains(id) &&
                !await SyncOutbox.instance.hasPendingLocalId('remito', id)) {
              await db.delete('remito_items',
                  where: 'remitoId = ?', whereArgs: [id]);
              await db.delete('remitos', where: 'id = ?', whereArgs: [id]);
              hubo = true;
            }
          }
          _remitosConfirmadosEnNube.remove(numero);
          continue;
        }
        remoteNumeros.add(numero);
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
          'saldoPendiente': data['saldoPendiente'] ??
              ((data['estadoPago']?.toString() == 'cobrado')
                  ? 0
                  : (data['total'] ?? 0)),
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
        hubo = true;

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

      // Capacidad 7: solo tombstones borran locales (no inferir por ausencia).
      _remitosConfirmadosEnNube.addAll(remoteNumeros);
      await _persistirWatermarkRemitos();

      if (hubo) DataRefreshHub.instance.notifyTodo();
      final pendiente = _snapRemitosPendiente;
      _snapRemitosPendiente = null;
      if (pendiente == null) break;
      actual = pendiente;
      }
    } catch (e) {
      debugPrint('Aplicar remitos remotos: $e');
    } finally {
      _sincronizandoRemitos = false;
    }
  }

  Future<void> _aplicarVentasRemotas(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_sincronizandoVentas) {
      _snapVentasPendiente = snap;
      return;
    }
    _sincronizandoVentas = true;
    try {
      var actual = snap;
      while (true) {
      final db = await DatabaseHelper.instance.database;
      var huboCambios = false;
      for (final doc in actual.docs) {
        try {
          final data = doc.data();
          final numero = data['numero']?.toString() ?? doc.id;
          if (numero.isEmpty) continue;

          if (isRemoteTombstone(data)) {
            final existentes = await db.query(
              'ventas',
              columns: ['id'],
              where: 'numero = ?',
              whereArgs: [numero],
              limit: 1,
            );
            if (existentes.isNotEmpty) {
              final id = (existentes.first['id'] as num?)?.toInt();
              if (id != null &&
                  !_colaVentas.contains(id) &&
                  !await SyncOutbox.instance.hasPendingLocalId('venta', id)) {
                await db.delete('pagos', where: 'ventaId = ?', whereArgs: [id]);
                await db.delete(
                  'ventas_items',
                  where: 'ventaId = ?',
                  whereArgs: [id],
                );
                await db.delete('ventas', where: 'id = ?', whereArgs: [id]);
                huboCambios = true;
              }
            }
            continue;
          }

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
      final pendiente = _snapVentasPendiente;
      _snapVentasPendiente = null;
      if (pendiente == null) break;
      actual = pendiente;
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

  bool _mapasDoublesIguales(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if ((b[e.key] ?? double.nan) != e.value) return false;
    }
    return true;
  }

  bool _productoSinCambiosRelevantes(Producto local, Producto merged) {
    return local.costo == merged.costo &&
        local.precio == merged.precio &&
        local.precio2 == merged.precio2 &&
        local.precio3 == merged.precio3 &&
        local.stock == merged.stock &&
        local.stockMinimo == merged.stockMinimo &&
        local.fotoPrincipal == merged.fotoPrincipal &&
        local.descripcion == merged.descripcion &&
        local.marca == merged.marca &&
        local.categoria == merged.categoria &&
        local.favorito == merged.favorito &&
        (local.deletedAt ?? '') == (merged.deletedAt ?? '') &&
        (local.actualizadoEn ?? '') == (merged.actualizadoEn ?? '') &&
        _mapasDoublesIguales(local.preciosListas, merged.preciosListas);
  }

  Future<void> _aplicarProductosRemotos(List<Producto> remotos) async {
    if (_sincronizando) {
      _productosPendientes = remotos;
      return;
    }
    _sincronizando = true;
    try {
      var actual = remotos;
      while (true) {
        final db = await DatabaseHelper.instance.database;
        final batch = db.batch();
        var huboCambios = false;
        for (final producto in actual) {
          final local =
              await _cache.buscarPorCodigoIncluyendoEliminados(producto.codigo);
          final locTs = _parseUtc(local?.actualizadoEn);
          final remTs = _parseUtc(producto.actualizadoEn);

          // LWW metadata: si lo local es más nuevo, solo tomar stock remoto
          // (Firestore es autoridad de stock vía increments).
          if (local != null &&
              locTs != null &&
              remTs != null &&
              locTs.isAfter(remTs)) {
            if (local.stock != producto.stock) {
              huboCambios = true;
              batch.update(
                'productos',
                {'stock': producto.stock},
                where: 'id = ?',
                whereArgs: [local.id],
              );
            }
            continue;
          }

          var merged = _fusionarProductoRemoto(producto, local);
          if (producto.estaEliminado) {
            merged = merged.copyWith(deletedAt: producto.deletedAt);
          }
          if (local != null && _productoSinCambiosRelevantes(local, merged)) {
            continue;
          }
          huboCambios = true;
          final data = merged.toMap();
          data['actualizadoEn'] = producto.actualizadoEn ??
              merged.actualizadoEn ??
              DateTime.now().toUtc().toIso8601String();
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
          DataRefreshHub.instance.notifyStock();
        }
        final pendiente = _productosPendientes;
        _productosPendientes = null;
        if (pendiente == null) break;
        actual = pendiente;
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
    // No bloquear el alta local si Firestore/Storage cuelga (modo avión).
    unawaited(() async {
      try {
        await remote.insertar(await _paraFirestore(conId));
      } catch (error) {
        debugPrint('Firestore insertar producto: $error');
      }
    }());
    return id;
  }

  @override
  Future<void> insertarLista(List<Producto> productos) async {
    await local.insertarLista(productos);
    unawaited(() async {
      try {
        final remotos = <Producto>[];
        for (final p in productos) {
          remotos.add(await _paraFirestore(p));
        }
        await remote.insertarLista(remotos);
      } catch (error) {
        debugPrint('Firestore insertarLista productos: $error');
      }
    }());
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
    unawaited(() async {
      try {
        // Fase 2: no pisar stock absoluto (va por ajustes atómicos).
        await remote.actualizarSinStock(await _paraFirestore(producto));
      } catch (error) {
        debugPrint('Firestore actualizar producto: $error');
      }
    }());
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
        actualizadoEn: DateTime.now().toUtc().toIso8601String(),
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
