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
import '../domain/domain_bootstrap.dart';
import '../domain/domain_event.dart';
import '../domain/inventory_ledger_service.dart';
import '../events/data_refresh_hub.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../utils/media_path.dart';
import 'media_sync_service.dart';
import 'cloud_sync_throttle.dart';
import 'observability/sync_circuit_breaker.dart';
import 'observability/sync_observability_hub.dart';
import 'observability/sync_path_logger.dart';
import 'scheduler/sync_priority.dart';
import 'scheduler/sync_scheduler.dart';
import 'sync_background.dart';
import 'sync_catchup.dart';
import 'sync_health.dart';
import 'sync_outbox.dart';
import 'sync_tombstone.dart';
import 'stock_ops_pull_policy.dart';
import 'stock_ops_pull_hold_store.dart';
import 'stock_ops_watermark.dart';
import 'stock_ops_applied_store.dart';
import 'stable_document_id.dart';
import 'sync_watermark_store.dart';
import 'windows_sync_policy.dart';
import '../integrity/legacy_ledger_migration.dart';
import '../../services/cuenta_corriente_service.dart';
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

  /// Último estado legible para la UI (sin carteles rojos agresivos).
  String syncStatusLabel = 'Local';
  String? syncStatusDetail;

  /// Reintento suave de outbox mientras la nube está activa (EXE→APK).
  Timer? _outboxPump;
  /// Evita doble start() en Windows (auth + shell reconectan a la vez).
  bool _windowsBootInProgress = false;
  bool _windowsPumpsActivos = false;
  /// Un empujón de remitos/ventas recientes (reopen ACK fantasma) por sesión.
  bool _windowsRecentDocsForced = false;
  /// Contador propio del outbox pump (NO reutilizar soft-pull: si no,
  /// tick queda en 0 y nunca drena productos → 350 pending eternos).
  // ignore: unused_field
  int _outboxDrainTickWindows = 0;

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
    final windows = PlatformCapabilities.isWindowsDesktop;
    // Flag síncrono ANTES de cualquier await (evita doble start en carrera).
    if (windows) {
      if (_windowsBootInProgress || _windowsPumpsActivos) {
        debugPrint('Sync Windows: start ignorado (ya activo)');
        return;
      }
      _windowsBootInProgress = true;
    }
    try {
      await stop();
      // stop() limpia flags Windows; reponer boot si aplica.
      if (windows) _windowsBootInProgress = true;

      // Trazabilidad E2E: cada hop lleva deviceId + tenant.
      SyncPathLogger.instance.configure(
        deviceId:
            '${Platform.operatingSystem}:${BackendConfigService.instance.tenantId}',
      );
      SyncPathLogger.instance.hop(
        stage: 'sync_start',
        entityType: 'engine',
        eventId: 'sync:start:${DateTime.now().toUtc().microsecondsSinceEpoch}',
        transactionId: 'boot',
        outcome: windows ? 'windows_boot' : 'mobile_boot',
        extra: {'tenant': BackendConfigService.instance.tenantId},
      );
      if (!windows) {
        await SyncOutbox.instance.reclaimStaleInflight();
        await _migrateLegacyPrefsColasOnce();
      }
      await _cargarWatermarksPersistidos();
      // 1.4.2: una sola vez rebobina watermark stock_ops 72h para recuperar
      // ops perdidas por avance prematuro (truncate/pending_apply).
      await _maybeRewindStockOpsWatermarkForConvergence();
      SyncHealthService.instance.firebaseReady = true;
      SyncHealthService.instance.canWrite = _puedeEscribirRemoto;
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail = null;

      if (!windows) {
        _usuariosSub = _usuariosRemote.watchTodos().listen(
          (lista) => unawaited(_aplicarUsuariosRemotos(lista)),
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
      }
      // Windows: SIN branding listener (snapshot + descarga logo tumbaba .exe).

      if (!windows) {
        // Solo cambios del snapshot (no reaplicar 10k productos en cada remito).
        _productosSub = _remote.watchSnapshots(limit: 10000).listen(
          _onProductosSnapshot,
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
        _documentosSub = _documentosCol.snapshots().listen(
          _aplicarDocumentosRemotos,
          onError: (Object error) => debugPrint('Sync documentos: $error'),
        );
        unawaited(_reintentarFotosLocalesPendientes());
      }

      // Empuja branding/permisos locales la primera vez si la nube no tiene.
      if (!windows) {
        unawaited(_publicarConfigLocalSiHaceFalta());
      }
      // Windows: publicarConfig SOLO tras cuarentena (y sin Storage).

      // Windows cuarentena: absorber outbox local SIN Firebase de colección.
      // Sin micro-drain, sin SafeMode, sin listeners, sin Storage.
      if (windows) {
        syncStatusLabel = 'Sincronizando…';
        syncStatusDetail = 'Arranque seguro…';
        syncInBackground(
          CloudSyncThrottle.enqueue(() async {
            try {
              await _maybeRewindStockOpsWatermarkForConvergence();
              syncStatusDetail = 'Revisando cola local…';
              DataRefreshHub.instance.notifyTodo();
              // Solo stock MUERTO/reclaim eterno — NO borrar pending frescos
              // (si no, el stock del .exe nunca llega al APK).
              // Boot: sin proveCloudApplied (N queries Firestore colgaban el
              // badge en "Limpiando cola…" y abortaban el seed/ledger).
              final purged = await SyncOutbox.instance.purgeStuckStockOps(
                minAttempts: 5,
                onlyLastErrorContains: 'reclaimed_stale_inflight',
                limit: 40,
                proveCloudApplied: null,
              );
              final recovered = await SyncOutbox.instance.recoverDeadStockOps(
                limit: 8,
                proveCloudApplied: (remoteOpId) =>
                    _remote.stockOpCloudApplied(remoteOpId),
              );
              if (purged > 0 ||
                  recovered.acked +
                          recovered.requeued +
                          recovered.forceRequeued >
                      0) {
                debugPrint(
                  'Outbox Windows: purge=$purged '
                  'deadAck=${recovered.acked} '
                  'deadReq=${recovered.requeued} '
                  'poisonForce=${recovered.forceRequeued}',
                );
              }
              // Histórico sin ledger → seed hasta vaciar (G4). Lotes chicos.
              try {
                await LegacyLedgerMigration.instance.seedUntilDone(
                  batchSize: 400,
                  maxBatches: 20,
                );
              } catch (e) {
                debugPrint('LegacyLedgerMigration boot: $e');
              }
              await SyncOutbox.instance.reclaimStaleInflight(
                olderThan: WindowsSyncPolicy.reclaimStaleInflightAfter,
              );
              await _migrateLegacyPrefsColasOnce();
              final orphans = await SyncOutbox.instance.ackOrphanUpserts();
              if (orphans > 0) {
                debugPrint('Outbox: ACK $orphans huérfanos');
              }

              final breakdown = await SyncOutbox.instance.pendingBreakdown();
              final pending = breakdown.values.fold<int>(0, (a, b) => a + b);
              if (pending > 0) {
                final que = SyncOutbox.formatBreakdown(breakdown);
                syncStatusLabel = 'Sincronizando…';
                syncStatusDetail =
                    '$pending pendientes: $que (arranque seguro)';
              } else {
                syncStatusLabel = 'En la nube (modo estable PC)';
                syncStatusDetail = null;
              }
              DataRefreshHub.instance.notifyTodo();
            } finally {
              _windowsBootInProgress = false;
              _iniciarPumpsWindows();
            }
          }, tag: 'startWindowsQuarantine'),
          tag: 'startWindowsQuarantine',
        );
        return;
      }

      // Primero bajar nube, después subir pendientes (evita pisar datos buenos).
      await _maybeRewindStockOpsWatermarkForConvergence();
      await _pullInicialCatchUp();
      // Android también debe cerrar legacy→ledger (antes solo Windows boot).
      try {
        await LegacyLedgerMigration.instance.seedUntilDone(
          batchSize: 500,
          maxBatches: 25,
        );
      } catch (e) {
        debugPrint('LegacyLedgerMigration mobile: $e');
      }
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
      _windowsBootInProgress = false;
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
      // Interactivo: sin demora artificial — la venta/precio debe verse ya.
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          await job();
          await _procesarOutboxDrain(
            maxBatches: 2,
            claimLimit: 8,
            entityTypes: const [
              'venta',
              'remito',
              'compra',
              'cliente',
              'stock_op',
            ],
          );
        }, tag: tag, interactive: true),
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

  /// Windows: listeners solo de negocio (colecciones chicas). Arrancar
  /// DESPUÉS de la cuarentena — no en el login frío.
  void _iniciarListenersNegocioWindows() {
    if (!PlatformCapabilities.isWindowsDesktop) return;
    if (!WindowsSyncPolicy.enableBusinessDocListeners(
      isWindowsDesktop: true,
    )) {
      return;
    }
    _ventasSub?.cancel();
    _remitosSub?.cancel();
    _clientesSub?.cancel();
    _comprasSub?.cancel();
    _ventasSub = _ventasCol.snapshots().listen(
      (snap) {
        syncInBackground(
          CloudSyncThrottle.enqueue(
            () => _aplicarVentasRemotas(snap),
            tag: 'listenVentasWin',
            interactive: true,
          ),
          tag: 'listenVentasWin',
        );
      },
      onError: (Object e) => debugPrint('Listen ventas Windows: $e'),
    );
    _remitosSub = _remitosCol.snapshots().listen(
      (snap) {
        syncInBackground(
          CloudSyncThrottle.enqueue(
            () => _aplicarRemitosRemotos(snap),
            tag: 'listenRemitosWin',
            interactive: true,
          ),
          tag: 'listenRemitosWin',
        );
      },
      onError: (Object e) => debugPrint('Listen remitos Windows: $e'),
    );
    _clientesSub = _clientesCol.snapshots().listen(
      (snap) {
        syncInBackground(
          CloudSyncThrottle.enqueue(
            () => _aplicarClientesRemotos(snap),
            tag: 'listenClientesWin',
            interactive: true,
          ),
          tag: 'listenClientesWin',
        );
      },
      onError: (Object e) => debugPrint('Listen clientes Windows: $e'),
    );
    _comprasSub = _comprasCol.snapshots().listen(
      (snap) {
        syncInBackground(
          CloudSyncThrottle.enqueue(
            () => _aplicarComprasRemotas(snap),
            tag: 'listenComprasWin',
            interactive: true,
          ),
          tag: 'listenComprasWin',
        );
      },
      onError: (Object e) => debugPrint('Listen compras Windows: $e'),
    );
    debugPrint(
      'Windows: listeners negocio ON '
      '(${WindowsSyncPolicy.windowsBusinessListenerCollections.join(", ")})',
    );
  }

  int _unifiedPumpTick = 0;

  void _iniciarOutboxPump() {
    _outboxPump?.cancel();
    // Un solo timer: inbound stock + drain outbox + soft docs.
    final windows = PlatformCapabilities.isWindowsDesktop;
    final intervalo = windows
        ? WindowsSyncPolicy.outboxPumpInterval
        : const Duration(seconds: 40);
    _outboxPump = Timer.periodic(intervalo, (_) {
      if (!_puedeEscribirRemoto) return;
      if (windows && !_windowsPumpsActivos) return;
      if (_actualizarAhoraBusy) return;
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          await SyncScheduler.instance.ensureRestored();
          await SyncScheduler.instance.runAutoHeal();
          await SyncOutbox.instance.ackOrphanUpserts();
          if (windows) {
            await SyncOutbox.instance.purgeStuckStockOps(
              minAttempts: 8,
              onlyLastErrorContains: 'reclaimed_stale_inflight',
              limit: 20,
              proveCloudApplied: null,
            );
          }
          await SyncOutbox.instance.reclaimStaleInflight(
            olderThan: windows
                ? WindowsSyncPolicy.reclaimStaleInflightAfter
                : const Duration(minutes: 5),
          );
          if (windows) {
            await _microCatchupDocsWindows();
          }

          // 1) Inbound stock_ops siempre (hardCap) — no esperar outbox vacío.
          try {
            await _tickInboundStockOps(windows: windows);
          } catch (e) {
            debugPrint('unifiedPump stock_ops: $e');
          }

          // 2) Outbound drain
          var pending = await SyncOutbox.instance.countByStatus(
            SyncOutboxStatus.pending,
          );

          if (pending > 0) {
            syncStatusDetail = '$pending pendientes…';
            await _procesarSchedulerTicks(windows: windows);
            pending = await SyncOutbox.instance.countByStatus(
              SyncOutboxStatus.pending,
            );
          }

          // 3) Soft docs (catálogo/negocio) — un lane por tick en Windows.
          try {
            if (windows && !_softPullBusy) {
              await _pullSuaveWindows();
            } else if (!windows && _unifiedPumpTick.isEven) {
              await _tickInboundDocsMobile();
            }
          } catch (e) {
            debugPrint('unifiedPump soft: $e');
          }
          _unifiedPumpTick++;

          final leftInflight = await SyncOutbox.instance.countByStatus(
            SyncOutboxStatus.inflight,
          );
          final prevLabel = syncStatusLabel;
          final prevDetail = syncStatusDetail;
          if (pending == 0 && leftInflight == 0) {
            syncStatusLabel = windows
                ? 'En la nube (modo estable PC)'
                : 'En la nube';
            syncStatusDetail = null;
          } else {
            syncStatusLabel = 'Sincronizando…';
            if (pending > 0) {
              final breakdown = await SyncOutbox.instance.pendingBreakdown();
              final que = SyncOutbox.formatBreakdown(breakdown);
              syncStatusDetail = que.isEmpty
                  ? '$pending pendientes'
                  : '$pending pendientes: $que';
            } else {
              syncStatusDetail = '$leftInflight en curso';
            }
          }
          if (prevLabel != syncStatusLabel || prevDetail != syncStatusDetail) {
            DataRefreshHub.instance.notifyTodo();
          }
        }, tag: 'outboxPump'),
        tag: 'outboxPump',
      );
    });
  }

  /// Pull stock_ops acotado (mismo hardCap anti-crash Windows).
  Future<void> _tickInboundStockOps({required bool windows}) async {
    if (_softPullBusy) return;
    await _runStockOpsLane(() async {
      if (windows) {
        final breakdown = await SyncOutbox.instance.pendingBreakdown();
        final pendingProd = breakdown['producto'] ?? 0;
        final budget = WindowsSyncPolicy.stockOpsPullBudget(
          pendingProductos: pendingProd,
        );
        await _pullStockOpsRemotas(
          maxPages: budget.maxPages,
          pageSize: budget.pageSize,
          maxApply: budget.maxApply,
          microBatchSize: 2,
          yieldMs: 150,
        );
        if (budget.recentLimit > 0) {
          await _pullStockOpsRecientes(
            limit: budget.recentLimit,
            maxApply: budget.maxApply,
          );
        }
        return;
      }
      await _pullStockOpsRemotas(maxPages: 2, pageSize: 40, maxApply: 20);
      await _pullStockOpsRecientes(limit: 60, maxApply: 20);
    });
  }

  Future<void> _tickInboundDocsMobile() async {
    try {
      final rem = await _remitosCol
          .orderBy('actualizadoEn', descending: true)
          .limit(20)
          .get();
      if (rem.docs.isNotEmpty) await _aplicarRemitosRemotos(rem);
      final ven = await _ventasCol
          .orderBy('actualizadoEn', descending: true)
          .limit(20)
          .get();
      if (ven.docs.isNotEmpty) await _aplicarVentasRemotas(ven);
    } catch (e) {
      debugPrint('unifiedPump docs mobile: $e');
    }
  }

  bool _actualizarAhoraBusy = false;
  /// Evita encolar soft-pulls encima si el anterior aún corre (crash EXE).
  bool _softPullBusy = false;
  /// Serializa apply de stock_ops (manual + soft-pull + pump).
  Future<void> _stockOpsLane = Future<void>.value();

  Future<T> _runStockOpsLane<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _stockOpsLane = _stockOpsLane.catchError((_) {}).then((_) async {
      try {
        done.complete(await job());
      } catch (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Actualización manual segura (UI: badge → "Actualizar ahora").
  ///
  /// Windows 1.4.12: stock-first + micro-rondas + pausa soft-pull + sin
  /// página de clientes. La ráfaga previa (negocio+stock+drain) tumbaba
  /// el .exe y dejaba stock divergente a mitad de apply.
  Future<Map<String, dynamic>> actualizarAhora() async {
    if (_actualizarAhoraBusy) {
      return {'ok': false, 'error': 'already_running'};
    }
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return {'ok': false, 'error': 'firebase_off'};
    }
    _actualizarAhoraBusy = true;
    final sw = Stopwatch()..start();
    final windows = PlatformCapabilities.isWindowsDesktop;
    try {
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail = 'Actualización manual…';

      Map<String, dynamic> result = {'ok': false};
      await CloudSyncThrottle.enqueueBackground(() async {
        result = await _actualizarAhoraBody(windows: windows, sw: sw);
      }, tag: 'actualizarAhora');
      return result;
    } catch (e) {
      syncStatusLabel = 'Sync con errores';
      syncStatusDetail = e.toString();
      return {'ok': false, 'error': e.toString()};
    } finally {
      _actualizarAhoraBusy = false;
    }
  }


  Future<Map<String, dynamic>> _actualizarAhoraBody({
    required bool windows,
    required Stopwatch sw,
  }) async {
    try {
      if (windows) {
        final breakdown = await SyncOutbox.instance.pendingBreakdown();
        final pendingProd = breakdown['producto'] ?? 0;
        final budget = WindowsSyncPolicy.manualRefreshBudgetWindows(
          pendingProductos: pendingProd,
        );
        var stockAppliedHint = 0;

        // Fase 1 — STOCK primero (convergencia EXE↔APK).
        try {
          try {
            await _remote.reconcilizarStockOpsPendientes(limit: 6);
          } catch (e) {
            debugPrint('actualizarAhora reconcilizar: $e');
          }
          await _runStockOpsLane(() async {
            for (var round = 0; round < budget.stockRounds; round++) {
              await _pullStockOpsRemotas(
                maxPages: budget.stockMaxPages,
                pageSize: budget.stockPageSize,
                maxApply: budget.stockMaxApply,
                microBatchSize: budget.stockMicroBatch,
                yieldMs: budget.yieldMs,
              );
              await Future<void>.delayed(
                Duration(milliseconds: budget.yieldMs),
              );
              await _pullStockOpsRecientes(
                limit: budget.stockRecentLimit,
                maxApply: budget.stockMaxApply,
                microBatchSize: budget.stockMicroBatch,
                yieldMs: budget.yieldMs,
              );
              await Future<void>.delayed(
                Duration(milliseconds: budget.yieldMs),
              );
              stockAppliedHint += await _sweepStockOpsHolds(limit: 4);
              await Future<void>.delayed(
                Duration(milliseconds: budget.yieldMs),
              );
            }
          });
        } catch (e) {
          debugPrint('actualizarAhora stock_ops: $e');
        }

        // Fase 1b — proyección local vs ledger (crash mid-apply).
        try {
          final repaired = await InventoryLedgerService.instance
              .repararProyeccionesDivergentes(limit: 60);
          if (repaired > 0) {
            debugPrint('actualizarAhora reparación proyección: $repaired');
          }
        } catch (e) {
          debugPrint('actualizarAhora reparación: $e');
        }

        // Fase 2 — config liviana (opcional).
        if (budget.pullConfig) {
          try {
            await _pullConfigWindowsLane('listas');
            await Future<void>.delayed(
              Duration(milliseconds: budget.yieldMs),
            );
            await _pullConfigWindowsLane('categorias');
          } catch (e) {
            debugPrint('actualizarAhora config: $e');
          }
        }

        // Fase 3 — negocio mínimo (no clientes masivos).
        try {
          await _pullNegocioRecienteWindows(limit: budget.negocioLimit);
        } catch (e) {
          debugPrint('actualizarAhora negocio: $e');
        }

        if (budget.pullClientes && budget.clientesPage > 0) {
          try {
            final page = await _pullPaginaPorDocId(
              _col('clientes'),
              watermarkKey: _wmClientesDoc,
              pageSize: budget.clientesPage,
            );
            if (page.docs.isNotEmpty) {
              await _aplicarClientesRemotos(page);
            }
          } catch (e) {
            debugPrint('actualizarAhora clientes: $e');
          }
        }

        // Fase 4 — un tick de outbox (prioriza stock_op / docs).
        if (_puedeEscribirRemoto) {
          try {
            await SyncScheduler.instance.ensureRestored();
            for (var i = 0; i < budget.schedulerTicks; i++) {
              final bd = await SyncOutbox.instance.pendingBreakdown();
              if (bd.isEmpty) break;
              final claimed = await SyncScheduler.instance.claimForTick(
                breakdown: bd,
                isWindows: true,
              );
              if (claimed.isEmpty) break;
              await _ejecutarClaimedOps(
                claimed,
                yieldMs: budget.yieldMs,
                allowPreempt: false,
              );
            }
          } catch (e) {
            debugPrint('actualizarAhora drain: $e');
          }
        }
        debugPrint(
          'actualizarAhora Windows done stockHint=$stockAppliedHint '
          'ms=${sw.elapsedMilliseconds}',
        );
      } else {
        try {
          try {
            await _remote.reconcilizarStockOpsPendientes(limit: 20);
          } catch (_) {}
          await _runStockOpsLane(() async {
            await _pullStockOpsRemotas(maxPages: 2, pageSize: 40, maxApply: 40);
            await _pullStockOpsRecientes(limit: 50, maxApply: 40);
          });
          try {
            await InventoryLedgerService.instance
                .repararProyeccionesDivergentes(limit: 80);
          } catch (_) {}
          final rem = await _remitosCol
              .orderBy('actualizadoEn', descending: true)
              .limit(25)
              .get();
          if (rem.docs.isNotEmpty) await _aplicarRemitosRemotos(rem);
          final ven = await _ventasCol
              .orderBy('actualizadoEn', descending: true)
              .limit(25)
              .get();
          if (ven.docs.isNotEmpty) await _aplicarVentasRemotas(ven);
          final cli = await _col('clientes')
              .orderBy('actualizadoEn', descending: true)
              .limit(25)
              .get();
          if (cli.docs.isNotEmpty) await _aplicarClientesRemotos(cli);
          final listas = await _configDoc('listas_precios').get();
          if (listas.exists) {
            await _aplicarListasPreciosRemotas(listas);
          }
        } catch (e) {
          debugPrint('actualizarAhora mobile: $e');
        }
        if (_puedeEscribirRemoto) {
          try {
            await SyncScheduler.instance.ensureRestored();
            await _procesarSchedulerTicks(windows: false);
          } catch (e) {
            debugPrint('actualizarAhora drain: $e');
          }
        }
      }

      syncStatusLabel =
          windows ? 'En la nube (modo estable PC)' : 'En la nube';
      syncStatusDetail = 'Actualizado ahora';
      SyncHealthService.instance.recordCycle(durationMs: sw.elapsedMilliseconds);
      DataRefreshHub.instance.notifyTodo();
      return {
        'ok': true,
        'ms': sw.elapsedMilliseconds,
        'platform': windows ? 'windows' : 'mobile',
      };
    } catch (e) {
      syncStatusLabel = 'Sync con errores';
      syncStatusDetail = e.toString();
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Windows: encola ventas/compras/productos/clientes recientes sin .get() masivo.
  ///
  /// Esto es lo que se rompió al “aliviar” el .exe: el stock viajaba por
  /// stock_ops pero el resto quedaba solo local → APK en $0.
  Future<void> _microCatchupDocsWindows() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final force = !_windowsRecentDocsForced;
      if (force) _windowsRecentDocsForced = true;
      final already = await SyncOutbox.instance.pendingBreakdown();
      final pendingProd = already['producto'] ?? 0;
      // Primer ciclo: reabrir ACK fantasma solo de docs comerciales.
      final limitDocs = force ? 60 : 20;
      final nRemitos = await SyncCatchup.instance.enqueueRecentDocumentCatchup(
        db: db,
        table: 'remitos',
        entityType: 'remito',
        limit: limitDocs,
        reopenAcked: force,
      );
      final nVentas = await SyncCatchup.instance.enqueueRecentDocumentCatchup(
        db: db,
        table: 'ventas',
        entityType: 'venta',
        limit: limitDocs,
        reopenAcked: force,
      );
      final nCompras = await SyncCatchup.instance.enqueueRecentDocumentCatchup(
        db: db,
        table: 'compras',
        entityType: 'compra',
        limit: force ? 40 : 12,
        reopenAcked: force,
      );
      // Si ya hay cientos de productos pending, NO encolar más (drenar primero).
      var nProductos = 0;
      if (pendingProd < 80) {
        nProductos = await SyncCatchup.instance.enqueueRecentDocumentCatchup(
          db: db,
          table: 'productos',
          entityType: 'producto',
          limit: force ? 40 : 20,
          reopenAcked: false,
        );
      }
      final nClientes = await SyncCatchup.instance.enqueueRecentDocumentCatchup(
        db: db,
        table: 'clientes',
        entityType: 'cliente',
        limit: force ? 40 : 12,
        reopenAcked: false,
      );
      final nProveedores =
          await SyncCatchup.instance.enqueueRecentDocumentCatchup(
        db: db,
        table: 'proveedores',
        entityType: 'proveedor',
        limit: force ? 30 : 10,
        reopenAcked: false,
      );
      // Catch-up secuencial chico — sin productos si la cola ya está llena.
      if (!force) {
        final tables = <(String, String)>[
          ('remitos', 'remito'),
          ('ventas', 'venta'),
          ('compras', 'compra'),
          ('clientes', 'cliente'),
          if (pendingProd < 80) ('productos', 'producto'),
        ];
        for (final e in tables) {
          await SyncCatchup.instance.enqueueDocumentCatchup(
            db: db,
            table: e.$1,
            entityType: e.$2,
            pageSize: 20,
            maxPagesPerCycle: 1,
          );
        }
      }
      final total = nRemitos +
          nVentas +
          nCompras +
          nProductos +
          nClientes +
          nProveedores;
      if (total > 0) {
        debugPrint(
          'Windows catch-up: remitos=$nRemitos ventas=$nVentas '
          'compras=$nCompras productos=$nProductos clientes=$nClientes '
          'proveedores=$nProveedores force=$force pendingProd=$pendingProd',
        );
        syncStatusLabel = 'Sincronizando…';
        syncStatusDetail =
            'Subiendo datos al celular ($total: ventas/compras/productos…)';
        DataRefreshHub.instance.notifyTodo();
      }
    } catch (e) {
      debugPrint('Windows micro catch-up docs: $e');
    }
  }

  /// Windows: pumps tras cuarentena corta; reintenta si Auth aún no listo.
  void _iniciarPumpsWindows() {
    _windowsPumpsActivos = true;
    syncInBackground(
      _bootWindowsPumpsConRetry(),
      tag: 'bootWindowsPumps',
    );
  }

  /// Evita quedar eterno en "arranque 45s" con 0 intentos.
  Future<void> _bootWindowsPumpsConRetry() async {
    final breakdown0 = await SyncOutbox.instance.pendingBreakdown();
    final pending0 = breakdown0.values.fold<int>(0, (a, b) => a + b);
    final nProd0 = breakdown0['producto'] ?? 0;
    final q = WindowsSyncPolicy.quarantineForBacklog(
      pendingProductos: nProd0,
    );
    if (!_windowsPumpsActivos) return;
    if (pending0 == 0) {
      syncStatusLabel = 'En la nube (modo estable PC)';
      syncStatusDetail = null;
    } else {
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail =
          '$pending0 pendientes: ${SyncOutbox.formatBreakdown(breakdown0)} '
          '(empieza en ${q.inSeconds}s)';
    }
    DataRefreshHub.instance.notifyTodo();

    await Future<void>.delayed(q);
    if (!_windowsPumpsActivos) return;

    // Antes: si Auth no estaba listo al vencer la cuarentena, return silencioso
    // → pump nunca arrancaba y la UI quedaba en "arranque Xs" eterno.
    var authOk = _puedeEscribirRemoto;
    for (var i = 0; i < 12 && !authOk; i++) {
      if (!_windowsPumpsActivos) return;
      syncStatusLabel = 'Sincronizando…';
      syncStatusDetail =
          '$pending0 pendientes — esperando sesión de nube (${i + 1}/12)…';
      DataRefreshHub.instance.notifyTodo();
      await Future<void>.delayed(const Duration(seconds: 5));
      authOk = _puedeEscribirRemoto;
    }

    // Arrancar pump igual: cada tick chequéa Auth; no dejar cola huérfana.
    _iniciarOutboxPump();
    // Listeners de negocio (remitos/ventas/clientes/compras) — sync en segundos.
    // Productos + stock_ops: pump unificado (outbox).
    if (authOk) {
      _iniciarListenersNegocioWindows();
    }

    if (!authOk) {
      syncStatusLabel = 'Sin nube';
      syncStatusDetail =
          '$pending0 pendientes — reingresá o reactivá la nube en Configuración';
      DataRefreshHub.instance.notifyTodo();
      return;
    }

    await CloudSyncThrottle.enqueue(() async {
      if (!_windowsPumpsActivos || !_puedeEscribirRemoto) return;
      await SyncOutbox.instance.ackOrphanUpserts();
      await _microCatchupDocsWindows();
      // Productos primero (grueso de la cola del screenshot).
      await _procesarOutboxDrain(
        maxBatches: 3,
        claimLimit: 8,
        entityTypes: const ['producto', 'proveedor'],
      );
      await _procesarOutboxDrain(
        maxBatches: 2,
        claimLimit: 5,
        entityTypes: const [
          'venta',
          'remito',
          'compra',
          'cliente',
          'stock_op',
        ],
      );
      final breakdown = await SyncOutbox.instance.pendingBreakdown();
      final pending = breakdown.values.fold<int>(0, (a, b) => a + b);
      if (pending > 0) {
        syncStatusLabel = 'Sincronizando…';
        syncStatusDetail =
            '$pending pendientes: ${SyncOutbox.formatBreakdown(breakdown)}';
      } else {
        syncStatusLabel = 'En la nube (modo estable PC)';
        syncStatusDetail = null;
      }
      DataRefreshHub.instance.notifyTodo();
    }, tag: 'primerDrainPostCuarentena');

    syncInBackground(
      CloudSyncThrottle.enqueue(
        _publicarConfigLocalSiHaceFalta,
        tag: 'publicarConfigPostCuarentena',
      ),
      tag: 'publicarConfigPostCuarentena',
    );

    // Soft-pull / pull productos un poco después del primer drain.
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (!_windowsPumpsActivos || !_puedeEscribirRemoto) return;
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          try {
            await _pullProductosIncrementalWindows(maxPages: 2, pageSize: 25);
            await _pullConfigWindowsLane('listas');
            await _pullConfigWindowsLane('branding_text');
          } catch (e) {
            debugPrint('Primer pull productos/config Windows: $e');
          }
        }, tag: 'primerPullProductosWindows'),
        tag: 'primerPullProductosWindows',
      );
    });

    // Soft-pull ya corre en el pump unificado (no timer paralelo).
  }

  static const _wmProductosDoc = 'pull_productos_doc';
  static const _wmProductosTs = 'pull_productos_ts';

  static const _wmClientesDoc = 'pull_clientes_doc';
  static const _wmVentasDoc = 'pull_ventas_doc';
  static const _wmRemitosDoc = 'pull_remitos_doc';
  static const _wmStockOpsDoc = 'pull_stock_ops_doc';
  /// Rebobina watermark stock_ops (recupera ops perdidas por avance prematuro
  /// o por starvation Windows tras cola de productos / WhatsApp-listas).
  /// v1.4.27: una sola vez — 30 días.
  Future<void> _maybeRewindStockOpsWatermarkForConvergence() async {
    // Fase 3: NO rebobinar watermark.
    // El rewind de 30 días re-aplicaba historia y empeoraba stock.
    // Convergencia = push outbox + pull stock_ops acotado (hardCap).
    return;
  }


  Future<QuerySnapshot<Map<String, dynamic>>> _pullPaginaPorDocId(
    CollectionReference<Map<String, dynamic>> col, {
    required String watermarkKey,
    int pageSize = 80,
  }) async {
    final meta = await SyncWatermarkStore.instance.loadMap(watermarkKey);
    var afterId = meta['afterDocId']?.toString();
    Query<Map<String, dynamic>> q =
        col.orderBy(FieldPath.documentId).limit(pageSize);
    if (afterId != null && afterId.isNotEmpty) {
      q = q.startAfter([afterId]);
    }
    final snap = await q.get();
    if (snap.docs.isNotEmpty) {
      await SyncWatermarkStore.instance.saveMap(watermarkKey, {
        'afterDocId': snap.docs.last.id,
        if (snap.docs.length < pageSize)
          'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } else if (afterId != null) {
      // Fin de barrido: reinicia cursor para la próxima ronda.
      await SyncWatermarkStore.instance.saveMap(watermarkKey, {
        'afterDocId': '',
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return snap;
  }

  int _softPullTickWindows = 0;

  /// Remitos/ventas más recientes por `actualizadoEn` (no depende del
  /// watermark lento por documentId). Idempotente por número.
  Future<void> _pullNegocioRecienteWindows({int limit = 25}) async {
    try {
      final rem = await _remitosCol
          .orderBy('actualizadoEn', descending: true)
          .limit(limit)
          .get();
      if (rem.docs.isNotEmpty) {
        await _aplicarRemitosRemotos(rem);
      }
    } catch (e) {
      debugPrint('pull remitos recientes Windows: $e');
    }
    try {
      final ven = await _ventasCol
          .orderBy('actualizadoEn', descending: true)
          .limit(limit)
          .get();
      if (ven.docs.isNotEmpty) {
        await _aplicarVentasRemotas(ven);
      }
    } catch (e) {
      debugPrint('pull ventas recientes Windows: $e');
    }
  }

  /// Una sola colección por tick. Con outbox quieto prioriza negocio + stock.
  Future<void> _pullSuaveWindows() async {
    if (_softPullBusy || _actualizarAhoraBusy) return;
    _softPullBusy = true;
    try {
      await _pullSuaveWindowsBody();
    } finally {
      _softPullBusy = false;
    }
  }

  Future<void> _pullSuaveWindowsBody() async {
    const page = 15;
    final tick = _softPullTickWindows;
    _softPullTickWindows++;
    final breakdown = await SyncOutbox.instance.pendingBreakdown();
    final pendingProd = breakdown['producto'] ?? 0;
    final prioritize = WindowsSyncPolicy.prioritizeBusinessConvergence(
      pendingProductos: pendingProd,
    );
    // Siempre (si quieto): tirón de remitos/ventas recientes antes del lane.
    final recentLimit = WindowsSyncPolicy.recentBusinessDocsLimit(
      pendingProductos: pendingProd,
    );
    if (recentLimit > 0 && tick % 2 == 0) {
      await _pullNegocioRecienteWindows(limit: recentLimit);
    }
    final lane = WindowsSyncPolicy.softPullLane(
      tick,
      prioritizeStockOps: prioritize,
    );
    try {
      switch (lane) {
        case 'productos_inc':
          await _pullProductosIncrementalWindows(maxPages: 1, pageSize: page);
        case 'productos_cat':
          await _pullProductosCatalogoWindows(maxPages: 1, pageSize: page);
        case 'clientes':
          final snap = await _pullPaginaPorDocId(
            _clientesCol,
            watermarkKey: _wmClientesDoc,
            pageSize: page,
          );
          await _aplicarClientesRemotos(snap);
        case 'ventas':
          if (prioritize) {
            await _pullNegocioRecienteWindows(limit: recentLimit > 0 ? recentLimit : 20);
          } else {
            final snap = await _pullPaginaPorDocId(
              _ventasCol,
              watermarkKey: _wmVentasDoc,
              pageSize: page,
            );
            await _aplicarVentasRemotas(snap);
          }
        case 'remitos':
          if (prioritize) {
            await _pullNegocioRecienteWindows(limit: recentLimit > 0 ? recentLimit : 20);
          } else {
            final snap = await _pullPaginaPorDocId(
              _remitosCol,
              watermarkKey: _wmRemitosDoc,
              pageSize: page,
            );
            await _aplicarRemitosRemotos(snap);
          }
        case 'stock_ops':
          final budget = WindowsSyncPolicy.stockOpsPullBudget(
            pendingProductos: pendingProd,
          );
          await _runStockOpsLane(() async {
            await _pullStockOpsRemotas(
              maxPages: budget.maxPages,
              pageSize: budget.pageSize,
              maxApply: budget.maxApply,
              microBatchSize: 3,
              yieldMs: 120,
            );
            if (budget.recentLimit > 0) {
              await _pullStockOpsRecientes(
                limit: budget.recentLimit,
                maxApply: budget.maxApply,
                microBatchSize: 3,
                yieldMs: 120,
              );
            }
            await _sweepStockOpsHolds(limit: 8);
          });
        case 'compras':
          final snap = await _pullPaginaPorDocId(
            _comprasCol,
            watermarkKey: 'pull_compras_doc',
            pageSize: page,
          );
          await _aplicarComprasRemotas(snap);
        case 'proveedores':
          final snap = await _pullPaginaPorDocId(
            _proveedoresCol,
            watermarkKey: 'pull_proveedores_doc',
            pageSize: page,
          );
          await _aplicarProveedoresRemotos(snap);
        case 'listas':
        case 'categorias':
        case 'permisos':
        case 'branding_text':
          await _pullConfigWindowsLane(lane);
      }
    } catch (e) {
      debugPrint('Pull suave Windows tick=$tick lane=$lane: $e');
    }
  }

  /// Config de nube → PC (get único, sin listeners ni descarga de logo).
  Future<void> _pullConfigWindowsLane(String lane) async {
    switch (lane) {
      case 'listas':
        final snap = await _configDoc('listas_precios').get();
        await _aplicarListasPreciosRemotas(snap);
      case 'categorias':
        final snap = await _configDoc('categorias').get();
        await _aplicarCategoriasRemotas(snap);
      case 'permisos':
        final snap = await _configDoc('permisos').get();
        await _aplicarPermisosRemotos(snap);
      case 'branding_text':
        final snap = await _configDoc('branding').get();
        await _aplicarBrandingRemoto(snap);
    }
  }

  /// Productos tocados recientemente (incluye stock vía increments).
  Future<void> _pullProductosIncrementalWindows({
    int maxPages = 2,
    int pageSize = 100,
  }) async {
    final meta = await SyncWatermarkStore.instance.loadMap(_wmProductosTs);
    var afterTs = meta['afterTs']?.toString();
    for (var i = 0; i < maxPages; i++) {
      final page = await _remote.obtenerActualizadosDesde(
        afterTs: afterTs,
        limit: pageSize,
      );
      if (page.items.isEmpty) break;
      await _aplicarProductosRemotos(page.items);
      if (page.lastTs != null && page.lastTs!.isNotEmpty) {
        afterTs = page.lastTs;
        await SyncWatermarkStore.instance.saveMap(_wmProductosTs, {
          'afterTs': afterTs,
        });
      }
      if (page.done) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Barrido completo del catálogo por documentId (sin techo 800 A-Z).
  Future<void> _pullProductosCatalogoWindows({
    int maxPages = 2,
    int pageSize = 120,
    bool forceRestart = false,
  }) async {
    final meta = await SyncWatermarkStore.instance.loadMap(_wmProductosDoc);
    var afterId = meta['afterDocId']?.toString();
    final completed = meta['completed'] == true;
    // Si ya barrió todo, reinicia cada tanto para no quedar congelado.
    if (forceRestart) {
      afterId = null;
    } else if (completed) {
      final lastDone = DateTime.tryParse(meta['completedAt']?.toString() ?? '');
      final stale = lastDone == null ||
          DateTime.now().toUtc().difference(lastDone) >
              const Duration(minutes: 30);
      if (!stale) return;
      afterId = null;
    }
    for (var i = 0; i < maxPages; i++) {
      final page = await _remote.obtenerPaginaPorDocId(
        afterDocId: afterId,
        limit: pageSize,
      );
      if (page.items.isEmpty) {
        await SyncWatermarkStore.instance.saveMap(_wmProductosDoc, {
          'afterDocId': afterId,
          'completed': true,
          'completedAt': DateTime.now().toUtc().toIso8601String(),
        });
        break;
      }
      await _aplicarProductosRemotos(page.items);
      afterId = page.lastDocId;
      await SyncWatermarkStore.instance.saveMap(_wmProductosDoc, {
        'afterDocId': afterId,
        'completed': page.done,
        if (page.done)
          'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (page.done) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Trae el estado de la nube con paginación (nunca `.get()` completo).
  /// En Windows hace pocas páginas; el resto lo completa el pull suave.
  Future<void> _pullInicialCatchUp() async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    final windows = PlatformCapabilities.isWindowsDesktop;
    Future<void> pausa() async {
      if (windows) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }

    // Windows: catch-up mínimo; el resto lo completa el pull suave (anti-crash).
    final maxDocPages = windows ? 1 : 50;
    final pageSize = windows ? 30 : 100;

    try {
      await _pullColeccionPaginada(
        _clientesCol,
        apply: _aplicarClientesRemotos,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial clientes: $e');
    }
    await pausa();
    try {
      await _pullColeccionPaginada(
        _proveedoresCol,
        apply: _aplicarProveedoresRemotos,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial proveedores: $e');
    }
    await pausa();
    try {
      if (windows) {
        // Solo 1 página chica de productos; catálogo/stock_ops → pull suave.
        await _pullProductosIncrementalWindows(maxPages: 1, pageSize: 25);
      } else {
        await _pullProductosCatalogoWindows(
          maxPages: maxDocPages,
          pageSize: pageSize,
          forceRestart: true,
        );
      }
    } catch (e) {
      debugPrint('Pull inicial productos: $e');
    }
    await pausa();
    try {
      await _pullColeccionPaginada(
        _ventasCol,
        apply: _aplicarVentasRemotas,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial ventas: $e');
    }
    await pausa();
    try {
      await _pullColeccionPaginada(
        _remitosCol,
        apply: _aplicarRemitosRemotos,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial remitos: $e');
    }
    await pausa();
    try {
      await _pullColeccionPaginada(
        _comprasCol,
        apply: _aplicarComprasRemotas,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial compras: $e');
    }
    await pausa();
    try {
      await _pullColeccionPaginada(
        _documentosCol,
        apply: _aplicarDocumentosRemotos,
        maxPages: maxDocPages,
        pageSize: pageSize,
        pausa: pausa,
      );
    } catch (e) {
      debugPrint('Pull inicial documentos: $e');
    }
    // Windows: cupo mínimo de stock_ops (antes omitido → diverge EXE↔APK).
    // Android: convergencia completa vía stock_ops → ledger.
    await pausa();
    try {
      if (windows) {
        final b = WindowsSyncPolicy.windowsCatchupStockOpsBudget();
        await _runStockOpsLane(() async {
          await _pullStockOpsRemotas(
            maxPages: b.maxPages,
            pageSize: b.pageSize,
            maxApply: b.maxApply,
            microBatchSize: 2,
            yieldMs: 200,
          );
        });
      } else {
        await _pullStockOpsRemotas(
          maxPages: maxDocPages,
          pageSize: pageSize,
        );
      }
    } catch (e) {
      debugPrint('Pull inicial stock_ops: $e');
    }
  }

  /// APK + Windows: tira stock_ops periódicos.
  ///
  /// Windows tenía solo soft-pull round-robin: con cola de productos
  /// (WhatsApp/listas) stock_ops caía a ~1/30 ticks → diverge horas.
  /// Pump dedicado con [WindowsSyncPolicy.stockOpsHardCap] (anti-crash).

  /// Aplica una lista de docs stock_ops al ledger (sin re-upload).
  Future<
      ({
        int applied,
        int consideredValid,
        int skippedMissingProduct,
        int skippedPendingApply,
        bool truncatedByMaxApply,
        List<({String opId, String reason, String? codigo, int? delta, String? at})>
            holds,
      })> _aplicarStockOpsItems(
    List<Map<String, dynamic>> items, {
    int? maxApply,
    int? microBatchSize,
    int yieldMs = 0,
  }) async {
    DomainBootstrap.ensureInitialized();
    final limit = maxApply ?? items.length;
    final batch = <({
      String opId,
      int productoId,
      String codigo,
      int delta,
      String? documentType,
      String? documentId,
    })>[];
    final holds = <({
      String opId,
      String reason,
      String? codigo,
      int? delta,
      String? at,
    })>[];
    var consideredValid = 0;
    var skippedMissingProduct = 0;
    var skippedPendingApply = 0;
    var truncatedByMaxApply = false;
    for (final op in items) {
      if (batch.length >= limit) {
        truncatedByMaxApply = true;
        break;
      }
      final opId = op['opId']?.toString() ?? '';
      final codigo = op['codigo']?.toString().trim() ?? '';
      final delta = (op['delta'] as num?)?.toInt() ?? 0;
      final status = op['status']?.toString() ?? '';
      final at = op['at']?.toString();
      if (opId.isEmpty || codigo.isEmpty || delta == 0) {
        // Malformed: park si hay opId (no avanzar a ciegas perdiendo la op).
        if (opId.isNotEmpty) {
          holds.add((
            opId: opId,
            reason: 'malformed',
            codigo: codigo.isEmpty ? null : codigo,
            delta: delta == 0 ? null : delta,
            at: at,
          ));
        }
        continue;
      }
      if (status == 'pending_apply' || status == 'claimed') {
        skippedPendingApply++;
        holds.add((
          opId: opId,
          reason: StockOpsPullHoldStore.reasonPendingApply,
          codigo: codigo,
          delta: delta,
          at: at,
        ));
        continue;
      }
      consideredValid++;
      // Dedupe durable (local-origin o remote ya aplicado).
      if (await StockOpsAppliedStore.instance.contains(opId)) {
        // Ya aplicada: si estaba en holds, liberar.
        await StockOpsPullHoldStore.instance.remove(opId);
        continue;
      }

      final local = await _cache.buscarPorCodigo(codigo);
      if (local?.id == null) {
        skippedMissingProduct++;
        holds.add((
          opId: opId,
          reason: StockOpsPullHoldStore.reasonMissingProduct,
          codigo: codigo,
          delta: delta,
          at: at,
        ));
        continue;
      }

      final meta = resolveStockOpDocumentMeta(
        opId: opId,
        documentType: op['documentType']?.toString(),
        documentId: op['documentId']?.toString(),
      );
      batch.add((
        opId: opId,
        productoId: local!.id!,
        codigo: codigo,
        delta: delta,
        documentType: meta.documentType,
        documentId: meta.documentId,
      ));
    }
    if (batch.isEmpty) {
      return (
        applied: 0,
        consideredValid: consideredValid,
        skippedMissingProduct: skippedMissingProduct,
        skippedPendingApply: skippedPendingApply,
        truncatedByMaxApply: truncatedByMaxApply,
        holds: holds,
      );
    }
    final n = await InventoryLedgerService.instance.applyRemoteStockOpsBatch(
      batch,
      microBatchSize: microBatchSize,
      yieldMs: yieldMs,
    );
    for (final op in batch) {
      await StockOpsPullHoldStore.instance.remove(op.opId);
    }
    if (n > 0) {
      debugPrint('stock_ops inbound: $n aplicadas');
      DataRefreshHub.instance.notifyStock();
      DataRefreshHub.instance.notifyProductos();
    }
    return (
      applied: n,
      consideredValid: consideredValid,
      skippedMissingProduct: skippedMissingProduct,
      skippedPendingApply: skippedPendingApply,
      truncatedByMaxApply: truncatedByMaxApply,
      holds: holds,
    );
  }

  /// Near-live: últimas N ops (APK) — idempotente; no mueve watermark.
  Future<void> _pullStockOpsRecientes({
    int limit = 40,
    int? maxApply,
    int? microBatchSize,
    int yieldMs = 0,
  }) async {
    final items = await _remote.obtenerStockOpsRecientes(limit: limit);
    if (items.isEmpty) return;
    // Firestore trae desc; aplicar en orden cronológico.
    final chronological = items.reversed.toList(growable: false);
    await _aplicarStockOpsItems(
      chronological,
      maxApply: maxApply,
      microBatchSize: microBatchSize,
      yieldMs: yieldMs,
    );
  }

  /// Aplica stock_ops remotos al ledger local (sin re-upload).
  /// Watermark por `at`+docId; NO avanza si se saltaron ops (producto,
  /// pending_apply) o si maxApply truncó la página a mitad.
  Future<void> _pullStockOpsRemotas({
    int maxPages = 5,
    int pageSize = 80,
    int? maxApply,
    int? microBatchSize,
    int yieldMs = 0,
  }) async {
    DomainBootstrap.ensureInitialized();
    // Antes del pull: sanear pending_apply que traban el cursor.
    try {
      final lim = PlatformCapabilities.isWindowsDesktop ? 8 : 25;
      await _remote.reconcilizarStockOpsPendientes(limit: lim);
    } catch (e) {
      debugPrint('stock_ops reconcilizar pre-pull: $e');
    }
    final meta = await SyncWatermarkStore.instance.loadMap(_wmStockOpsDoc);
    // Migración: watermark viejo solo-docId (UUID) → reiniciar por tiempo.
    final cursor = migrateStockOpsWatermark(meta);
    var afterId = cursor.afterId;
    var afterAt = cursor.afterAt;
    var appliedTotal = 0;
    final limitApply = maxApply ?? (pageSize * maxPages);

    for (var i = 0; i < maxPages; i++) {
      if (appliedTotal >= limitApply) break;
      final page = await _remote.obtenerStockOpsPagina(
        afterDocId: afterId.isEmpty ? null : afterId,
        afterAt: afterAt.isEmpty ? null : afterAt,
        limit: pageSize,
      );
      if (page.items.isEmpty) {
        await SyncWatermarkStore.instance.saveMap(_wmStockOpsDoc, {
          'afterDocId': afterId,
          'afterAt': afterAt,
          'v': 'at_v2',
          'completedAt': DateTime.now().toUtc().toIso8601String(),
        });
        break;
      }

      final remaining = limitApply - appliedTotal;
      var result = await _aplicarStockOpsItems(
        page.items,
        maxApply: remaining,
        microBatchSize: microBatchSize,
        yieldMs: yieldMs,
      );
      // Si pending_apply bloquea, reconciliar y reintentar la misma página 1 vez.
      if (result.skippedPendingApply > 0 &&
          result.applied == 0 &&
          !result.truncatedByMaxApply) {
        try {
          await _remote.reconcilizarStockOpsPendientes(limit: 15);
          result = await _aplicarStockOpsItems(
            page.items,
            maxApply: remaining,
            microBatchSize: microBatchSize,
            yieldMs: yieldMs,
          );
        } catch (e) {
          debugPrint('stock_ops retry tras reconcilizar: $e');
        }
      }
      appliedTotal += result.applied;

      // Anti-HOL: persistir blockers en hold-set y avanzar watermark.
      for (final h in result.holds) {
        await StockOpsPullHoldStore.instance.upsert(
          opId: h.opId,
          reason: h.reason,
          codigo: h.codigo,
          delta: h.delta,
          at: h.at,
        );
      }
      final malformed = result.holds.where((h) => h.reason == 'malformed').length;
      final blockers = result.skippedMissingProduct +
          result.skippedPendingApply +
          malformed;
      final parked = blockers > 0 &&
          result.holds.length >= blockers &&
          !result.truncatedByMaxApply;

      if (!shouldAdvanceStockOpsWatermark(
        consideredValid: result.consideredValid,
        skippedMissingProduct: result.skippedMissingProduct,
        skippedPendingApply: result.skippedPendingApply + malformed,
        truncatedByMaxApply: result.truncatedByMaxApply,
        blockersParkedInHolds: parked,
      )) {
        debugPrint(
          'stock_ops watermark: hold '
          '(missingProduct=${result.skippedMissingProduct} '
          'pendingApply=${result.skippedPendingApply} '
          'truncated=${result.truncatedByMaxApply} '
          'parked=$parked holds=${result.holds.length})',
        );
        break;
      }

      afterId = page.lastDocId ?? afterId;
      afterAt = page.lastAt ?? afterAt;
      await SyncWatermarkStore.instance.saveMap(_wmStockOpsDoc, {
        'afterDocId': afterId,
        'afterAt': afterAt,
        'v': 'at_v2',
        if (page.done)
          'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (page.done || appliedTotal >= limitApply) break;
      if (PlatformCapabilities.isWindowsDesktop) {
        await Future<void>.delayed(
          Duration(milliseconds: yieldMs > 0 ? yieldMs : 400),
        );
      }
    }

    // Sweeper de holds (no bloquea watermark).
    await _sweepStockOpsHolds(limit: PlatformCapabilities.isWindowsDesktop ? 8 : 25);
  }

  /// Reintenta ops estacionadas en hold-set (pending_apply / missing product).
  Future<int> _sweepStockOpsHolds({int limit = 25}) async {
    final due = await StockOpsPullHoldStore.instance.listDue(limit: limit);
    if (due.isEmpty) return 0;
    try {
      await _remote.reconcilizarStockOpsPendientes(limit: limit);
    } catch (_) {}

    final items = <Map<String, dynamic>>[];
    for (final h in due) {
      final opId = h['op_id']?.toString() ?? '';
      final codigo = h['codigo']?.toString() ?? '';
      final delta = (h['delta'] as num?)?.toInt() ?? 0;
      if (opId.isEmpty || codigo.isEmpty || delta == 0) continue;
      try {
        var applied = await _remote.stockOpCloudApplied(opId);
        if (!applied) {
          // Completar ESTA op (no depender del limit random de reconcile).
          try {
            await _remote.ajustarStock(
              codigo: codigo,
              delta: delta,
              opId: opId,
            );
            applied = await _remote.stockOpCloudApplied(opId);
          } catch (e) {
            debugPrint('sweep complete $opId: $e');
          }
        }
        if (!applied) {
          await StockOpsPullHoldStore.instance.upsert(
            opId: opId,
            reason: h['reason']?.toString() ??
                StockOpsPullHoldStore.reasonPendingApply,
            codigo: codigo,
            delta: delta,
            at: h['op_at']?.toString(),
          );
          continue;
        }
        items.add({
          'opId': opId,
          'codigo': codigo,
          'delta': delta,
          'status': 'applied',
          'at': h['op_at']?.toString(),
        });
      } catch (e) {
        debugPrint('sweep hold $opId: $e');
      }
    }
    if (items.isEmpty) return 0;
    final result = await _aplicarStockOpsItems(items, maxApply: limit);
    for (final h in result.holds) {
      await StockOpsPullHoldStore.instance.upsert(
        opId: h.opId,
        reason: h.reason,
        codigo: h.codigo,
        delta: h.delta,
        at: h.at,
      );
    }
    if (result.applied > 0) {
      debugPrint('stock_ops holds sweep: ${result.applied} aplicadas');
      DataRefreshHub.instance.notifyStock();
      DataRefreshHub.instance.notifyProductos();
    }
    return result.applied;
  }

  /// Antes de hard-delete por tombstone: reverso local si el ledger neto ≠ 0.
  ///
  /// Hardening: busca neto por identidad estable (`numero`) y fallback
  /// legado (`localId`) — cada nodo tiene autoincrement distinto.
  Future<void> _reversoLocalAntesDeTombstone({
    required String documentType,
    required int localId,
    required String stableDocumentId,
    required String itemsTable,
    required String fkColumn,
  }) async {
    DomainBootstrap.ensureInitialized();
    final candidates = ledgerDocumentIdCandidates(
      numero: stableDocumentId,
      localId: localId,
    );
    var net = 0;
    var ledgerKey = stableDocumentId;
    for (final key in candidates) {
      final n = await InventoryLedgerService.instance.ledgerNetForDocument(
        documentType: documentType,
        documentId: key,
      );
      if (n != 0) {
        net = n;
        ledgerKey = key;
        break;
      }
    }
    if (net == 0) return;

    final db = await DatabaseHelper.instance.database;
    final items = await db.query(
      itemsTable,
      where: '$fkColumn = ?',
      whereArgs: [localId],
    );
    final lines = <InventoryLine>[];
    for (final item in items) {
      final productoId = (item['productoId'] as num?)?.toInt();
      if (productoId == null) continue;
      final cantidad = (item['cantidad'] as num?)?.toInt() ?? 0;
      if (cantidad == 0) continue;
      lines.add(InventoryLine(productoId: productoId, cantidad: cantidad));
    }
    if (lines.isEmpty) return;

    final rev = DateTime.now().toUtc().microsecondsSinceEpoch;
    final sign = net < 0 ? 1 : -1;
    final tipo = sign > 0 ? 'entrada' : 'salida';
    await InventoryLedgerService.instance.reverseDocumentLocally(
      documentType: documentType,
      documentId: ledgerKey,
      eventId: 'inv:tombstone_rev:$documentType:$stableDocumentId:$rev',
      lines: lines,
      sign: sign,
      movimientoTipo: tipo,
      motivo:
          'Reverso local por tombstone remoto $documentType#$stableDocumentId',
    );
  }

  /// Barrido paginado por documentId — evita `.get()` completo (R6).
  Future<void> _pullColeccionPaginada(
    CollectionReference<Map<String, dynamic>> col, {
    required Future<void> Function(QuerySnapshot<Map<String, dynamic>>) apply,
    required int maxPages,
    required int pageSize,
    required Future<void> Function() pausa,
  }) async {
    String? afterId;
    for (var i = 0; i < maxPages; i++) {
      Query<Map<String, dynamic>> q =
          col.orderBy(FieldPath.documentId).limit(pageSize);
      if (afterId != null && afterId.isNotEmpty) {
        q = q.startAfter([afterId]);
      }
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      await apply(snap);
      afterId = snap.docs.last.id;
      if (snap.docs.length < pageSize) break;
      await pausa();
    }
  }

  Future<void> _vaciarColasYSubirPendientes() async {
    final sw = Stopwatch()..start();
    String? cycleError;
    try {
      await SyncOutbox.instance.reclaimStaleInflight();
      await _migrateLegacyPrefsColasOnce();

      if (!_puedeEscribirRemoto) {
        SyncHealthService.instance.canWrite = false;
        return;
      }
      SyncHealthService.instance.canWrite = true;

      final windows = PlatformCapabilities.isWindowsDesktop;
      await _procesarOutboxBatch(limit: windows ? 5 : 80);

      // Config local pendiente (listas / categorías) tras cortes de red.
      if (await _isConfigPendiente(_prefsConfigListasPendiente)) {
        await subirListasPrecios();
      }
      if (await _isConfigPendiente(_prefsConfigCategoriasPendiente)) {
        await subirCategorias();
      }

      final db = await DatabaseHelper.instance.database;
      // Windows: NUNCA .get() completo de ausentes (tumba el .exe).
      if (!windows) {
        await _subirClientesAusentesEnNube(db);
        await _subirProveedoresAusentesEnNube(db);
        await _subirProductosAusentesEnNube(db);
        await _flushColaStockOps();

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
          maxBatches: 20,
          entityTypes: const ['venta', 'remito', 'compra', 'cliente'],
        );
        await _procesarOutboxDrain(maxBatches: 15);
      } else {
        await _procesarOutboxDrain(
          maxBatches: 1,
          claimLimit: 3,
          entityTypes: const ['venta', 'remito', 'compra', 'cliente'],
        );
      }
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
    final batch = await SyncOutbox.instance.claimBatch(
      limit: limit,
      orderByPriority: true,
    );
    await _ejecutarClaimedOps(batch);
  }

  /// Drain outbox por prioridad (claim fijo).
  Future<void> _procesarSchedulerTicks({required bool windows}) async {
    final ticks = windows ? 3 : 8;
    for (var i = 0; i < ticks; i++) {
      final breakdown = await SyncOutbox.instance.pendingBreakdown();
      if (breakdown.isEmpty) break;
      final claimed = await SyncScheduler.instance.claimForTick(
        breakdown: breakdown,
        isWindows: windows,
      );
      if (claimed.isEmpty) break;
      final yieldMs = windows ? 80 : 20;
      final preempted = await _ejecutarClaimedOps(
        claimed,
        yieldMs: yieldMs,
        allowPreempt: true,
      );
      if (preempted) {
        // Inmediatamente drenar L1 sin esperar próximo tick.
        final bd2 = await SyncOutbox.instance.pendingBreakdown();
        final crit = await SyncScheduler.instance.claimForTick(
          breakdown: bd2,
          isWindows: windows,
        );
        if (crit.isNotEmpty) {
          await _ejecutarClaimedOps(crit, yieldMs: windows ? 50 : 0);
        }
      }
      if (windows && i + 1 < ticks) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Ejecuta ops claimed; preempt si aparece L1 durante fondo.
  /// Retorna true si preemptó.
  Future<bool> _ejecutarClaimedOps(
    List<Map<String, dynamic>> batch, {
    int yieldMs = 0,
    bool allowPreempt = false,
  }) async {
    var preempted = false;
    for (var i = 0; i < batch.length; i++) {
      final op = batch[i];
      final opId = op['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final entityType = op['entity_type']?.toString() ?? '';
      final isBg = !SyncPriority.isCriticalEntity(entityType);

      // Preemption: si estamos en fondo y llegó venta/stock, abortar lote.
      if (allowPreempt && isBg && i > 0) {
        if (await SyncScheduler.instance.shouldPreempt()) {
          preempted = true;
          // Reencolar resto del lote (evita quedar inflight minutos).
          for (var j = i; j < batch.length; j++) {
            final restId = batch[j]['op_id']?.toString() ?? '';
            if (restId.isEmpty) continue;
            await SyncOutbox.instance.requeueImmediate(restId, reason: 'preempted_for_critical');
          }
          break;
        }
      }

      // Circuit breaker abierto: reencolar resto y salir (evitar storm).
      if (!SyncCircuitBreaker.instance.allowRequest()) {
        for (var j = i; j < batch.length; j++) {
          final restId = batch[j]['op_id']?.toString() ?? '';
          if (restId.isEmpty) continue;
          await SyncOutbox.instance.requeueImmediate(
            restId,
            reason: 'circuit_open',
          );
        }
        break;
      }

      final sw = Stopwatch()..start();
      var error = false;
      try {
        try {
          SyncObservabilityHub.instance.onSendStart(opId);
        } catch (_) {}
        await _ejecutarOutboxOp(op);
        await SyncOutbox.instance.ack(opId);
        SyncHealthService.instance.recordAck();
        try {
          SyncObservabilityHub.instance.onSendDone(
            opId,
            latencyMs: sw.elapsedMilliseconds,
            error: false,
          );
        } catch (_) {}
        final waitCb = SyncCircuitBreaker.instance.extraWaitMs;
        final totalYield = yieldMs + waitCb;
        if (totalYield > 0) {
          await Future<void>.delayed(Duration(milliseconds: totalYield));
        }
      } catch (e) {
        error = true;
        await SyncOutbox.instance.fail(opId, e);
        SyncHealthService.instance.recordFail();
        try {
          SyncObservabilityHub.instance.onSendDone(
            opId,
            latencyMs: sw.elapsedMilliseconds,
            error: true,
          );
        } catch (_) {}
        debugPrint('Outbox fail $opId: $e');
      } finally {
        await SyncScheduler.instance.recordOpResult(
          entityType: entityType,
          latencyMs: sw.elapsedMilliseconds,
          error: error,
          firestoreOk: _puedeEscribirRemoto,
        );
      }
    }
    return preempted;
  }

  /// Drena varios batches por ciclo (Capacidad 9). Prioridad siempre on.
  Future<void> _procesarOutboxDrain({
    int maxBatches = 20,
    List<String>? entityTypes,
    int? claimLimit,
  }) async {
    final windows = PlatformCapabilities.isWindowsDesktop;
    final limit = claimLimit ?? (windows ? 5 : 80);
    for (var i = 0; i < maxBatches; i++) {
      if (windows && i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
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
      final batch = await SyncOutbox.instance.claimBatch(
        limit: limit,
        entityTypes: entityTypes,
        orderByPriority: true,
      );
      if (batch.isEmpty) break;
      await _ejecutarClaimedOps(batch, yieldMs: windows ? 100 : 0);
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
      // G3: nunca ACK silencioso. Basura → fail (dead tras maxAttempts).
      throw StateError('stock_op outbox sin payload; no ACK');
    }
    final payload = jsonDecode(payloadRaw);
    if (payload is! Map) {
      throw StateError('stock_op outbox payload inválido; no ACK');
    }
    final map = Map<String, dynamic>.from(payload);
    final opId =
        map['opId']?.toString() ?? op['entity_remote_id']?.toString() ?? '';
    final codigo = map['codigo']?.toString() ?? '';
    final delta = (map['delta'] as num?)?.toInt() ?? 0;
    if (opId.isEmpty || codigo.isEmpty || delta == 0) {
      throw StateError(
        'stock_op outbox incompleto (opId/codigo/delta); no ACK',
      );
    }
    final documentType = map['documentType']?.toString();
    final documentId = map['documentId']?.toString();

    final windows = PlatformCapabilities.isWindowsDesktop;
    try {
      final future = _remote.ajustarStock(
        codigo: codigo,
        delta: delta,
        opId: opId,
        documentType: documentType,
        documentId: documentId,
      );
      if (windows) {
        await future.timeout(const Duration(seconds: 20));
      } else {
        await future;
      }
      // ACK del caller solo tras prueba cloud applied (idempotencia por op).
      final proven = await _remote.stockOpCloudApplied(opId);
      if (!proven) {
        throw StateError(
          'stock_op $opId sin status=applied en nube; no ACK',
        );
      }
      await StockOpsAppliedStore.instance.mark(
        opId: opId,
        origin: 'local',
        codigo: codigo,
        delta: delta,
      );

    } on TimeoutException {
      throw StateError('stock_op timeout Windows ($opId)');
    }
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
      case 'producto':
        await _col('productos').doc(remoteId).set({
          ...tombstone,
          'codigo': remoteId,
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
      case 'producto':
        if (localId != null) {
          await db.delete('productos', where: 'id = ?', whereArgs: [localId]);
        } else if (remoteId != null && remoteId.isNotEmpty) {
          await db.delete(
            'productos',
            where: 'codigo = ?',
            whereArgs: [remoteId],
          );
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

  /// One-shot: prefs legacy → SyncOutbox, luego borra las keys.
  /// Outbox SQLite es la única cola en runtime.
  Future<void> _migrateLegacyPrefsColasOnce() async {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'sync_outbox_migrated_v2';
    if (prefs.getBool(flag) == true) return;

    Set<int> readIds(String key) {
      final out = <int>{};
      for (final s in prefs.getStringList(key) ?? const []) {
        final id = int.tryParse(s);
        if (id != null) out.add(id);
      }
      return out;
    }

    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'cliente',
      ids: readIds(_prefsColaClientes),
    );
    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'proveedor',
      ids: readIds(_prefsColaProveedores),
    );
    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'producto',
      ids: readIds(_prefsColaProductos),
    );
    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'venta',
      ids: readIds(_prefsColaVentas),
    );
    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'remito',
      ids: readIds(_prefsColaRemitos),
    );
    await SyncOutbox.instance.migrateLegacyIdSet(
      entityType: 'compra',
      ids: readIds(_prefsColaCompras),
    );

    for (final token in prefs.getStringList(_prefsColaStockOps) ?? const []) {
      final parts = token.split('|');
      if (parts.length < 3) continue;
      final opId = parts[0];
      final codigo = parts[1];
      final delta = int.tryParse(parts[2]) ?? 0;
      if (opId.isEmpty || codigo.isEmpty || delta == 0) continue;
      await SyncOutbox.instance.enqueueStockOp(
        opId: opId,
        codigo: codigo,
        delta: delta,
      );
    }

    for (final key in [
      _prefsColaClientes,
      _prefsColaProveedores,
      _prefsColaProductos,
      _prefsColaVentas,
      _prefsColaRemitos,
      _prefsColaCompras,
      _prefsColaStockOps,
      'sync_stock_ops_hechas_v2',
      'sync_outbox_migrated_v1',
    ]) {
      await prefs.remove(key);
    }
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
    _windowsPumpsActivos = false;
    _windowsBootInProgress = false;
    _windowsRecentDocsForced = false;
    _outboxDrainTickWindows = 0;
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
      // Windows: solo texto (Storage deshabilitado — evita crash .exe).
      final payload = PlatformCapabilities.isWindowsDesktop
          ? BrandingService.instance.toFirestoreMap()
          : await BrandingService.instance.prepararPayloadNube();
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

  // Prefs legacy (solo lectura one-shot → outbox).
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
      // Hardening: paginado (nunca .get() completo).
      final remoteIds = <String>{};
      String? afterId;
      const pageSize = 80;
      const maxPages = 40; // tope duro por ciclo
      for (var i = 0; i < maxPages; i++) {
        Query<Map<String, dynamic>> q =
            _clientesCol.orderBy(FieldPath.documentId).limit(pageSize);
        if (afterId != null && afterId.isNotEmpty) {
          q = q.startAfter([afterId]);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final d in snap.docs) {
          remoteIds.add(d.id);
          final sid = d.data()['syncId']?.toString();
          if (sid != null && sid.isNotEmpty) remoteIds.add(sid);
        }
        afterId = snap.docs.last.id;
        if (snap.docs.length < pageSize) break;
      }
      final locales = await db.query(
        'clientes',
        columns: ['id', 'syncId', 'activo'],
      );
      var subidos = 0;
      for (final row in locales) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        final syncId = row['syncId']?.toString() ?? '';
        if (syncId.isNotEmpty && remoteIds.contains(syncId)) continue;
        if (remoteIds.contains('$id')) continue;
        await subirCliente(id, forzar: true);
        subidos++;
        if (subidos >= 50) break; // presupuesto por ciclo
      }
    } catch (e) {
      debugPrint('Subir clientes ausentes: $e');
    }
  }

  Future<void> _subirProveedoresAusentesEnNube(Database db) async {
    try {
      // Hardening: paginado (nunca .get() completo).
      final remoteIds = <String>{};
      String? afterId;
      const pageSize = 80;
      const maxPages = 40;
      for (var i = 0; i < maxPages; i++) {
        Query<Map<String, dynamic>> q =
            _proveedoresCol.orderBy(FieldPath.documentId).limit(pageSize);
        if (afterId != null && afterId.isNotEmpty) {
          q = q.startAfter([afterId]);
        }
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final d in snap.docs) {
          remoteIds.add(d.id);
          final sid = d.data()['syncId']?.toString();
          if (sid != null && sid.isNotEmpty) remoteIds.add(sid);
        }
        afterId = snap.docs.last.id;
        if (snap.docs.length < pageSize) break;
      }
      final locales = await db.query(
        'proveedores',
        columns: ['id', 'syncId', 'activo'],
      );
      var subidos = 0;
      for (final row in locales) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        if (_asInt01(row['activo'], defaultValue: 1) == 0) continue;
        var syncId = row['syncId']?.toString() ?? '';
        if (syncId.isEmpty) {
          syncId = await asegurarSyncIdProveedor(id);
        }
        if (syncId.isEmpty) continue;
        if (remoteIds.contains(syncId)) continue;
        await subirProveedor(id, forzar: true);
        subidos++;
        if (subidos >= 50) break;
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
          // NUNCA absolute stock aquí: alta/import ya encolan stock_ops.
          // Absolute + increment = doble conteo cloud (auditoría forense).
          await subirProductoPorId(id, incluirStockAbsoluto: false, forzar: true);
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
  ///
  /// [documentType]/[documentId]: atribución al doc comercial (anular seguidor).
  Future<void> ajustarStockEnNube({
    required int productoId,
    required int delta,
    String? opId,
    bool flushImmediately = true,
    String? documentType,
    String? documentId,
    bool alreadyEnqueuedInTxn = false,
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

    // Dedupe inbound durable (NO es prueba de ACK en nube).
    await StockOpsAppliedStore.instance.mark(
      opId: idOp,
      origin: 'local',
      codigo: codigo,
      delta: delta,
    );
    if (!alreadyEnqueuedInTxn) {
      await SyncOutbox.instance.enqueueStockOp(
        opId: idOp,
        codigo: codigo,
        delta: delta,
        documentType: documentType,
        documentId: documentId,
      );
    }
    // Windows: disparo safe (sin txn). ACK solo si cloud applied.
    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(() async {
          try {
            await _remote
                .ajustarStock(
                  codigo: codigo,
                  delta: delta,
                  opId: idOp,
                  documentType: documentType,
                  documentId: documentId,
                )
                .timeout(const Duration(seconds: 20));
            final proven = await _remote.stockOpCloudApplied(idOp);
            if (!proven) {
              throw StateError('stock_op $idOp sin prueba applied en nube');
            }
            await SyncOutbox.instance.ack('stock_op:$idOp');
            debugPrint('Windows stock_op OK $idOp Δ$delta $codigo');
          } catch (e) {
            debugPrint('Windows stock_op fail (reintento pump): $e');
            await SyncOutbox.instance.fail('stock_op:$idOp', e);
          }
        }, tag: 'stockOpWinSafe', interactive: true),
        tag: 'stockOpWinSafe',
      );
      return;
    }

    if (flushImmediately) {
      await _flushColaStockOps();
    }
  }

  /// Expone flush diferido (Windows: tras compras, sin tumbar el .exe).
  Future<void> flushStockOpsPendientes() => _flushColaStockOps();

  Future<void> _flushColaStockOps() async {
    // Solo outbox (colas prefs legacy ya no se escriben).
    await _procesarOutboxDrain(
      maxBatches: 3,
      claimLimit: 8,
      entityTypes: const ['stock_op'],
    );
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
    } catch (e) {
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
            return;
          }
        }
      }
      await _proveedoresCol.doc(syncId).set(payload, SetOptions(merge: true));
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:proveedor:$proveedorId');
      }
    } catch (e) {
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
        // Huérfana: ACK vía caller (no reintentar eterno).
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
    } catch (e) {
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
        // Huérfana: ACK vía caller.
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
    } catch (e) {
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

  Future<void> eliminarProductoRemoto(String codigo, {int? localId}) async {
    final cod = codigo.trim();
    if (cod.isEmpty) return;
    await SyncOutbox.instance.enqueueDelete(
      entityType: 'producto',
      remoteId: cod,
      localId: localId,
    );
    if (!_puedeEscribirRemoto) return;

    Future<void> aplicar() async {
      try {
        await _aplicarTombstoneRemoto('producto', cod);
        await _borrarLocalTrasTombstone(
          entityType: 'producto',
          localId: localId,
          remoteId: cod,
        );
        await SyncOutbox.instance.ack('delete:producto:$cod');
      } catch (e) {
        await SyncOutbox.instance.fail('delete:producto:$cod', e);
        debugPrint('Firestore eliminar producto: $e');
      }
    }

    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(aplicar, tag: 'eliminarProductoRemoto'),
        tag: 'eliminarProductoRemoto',
      );
      return;
    }
    await aplicar();
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
        // Huérfana: ACK vía caller.
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
    } catch (e) {
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
    bool forceBackground = false,
  }) async {
    if (!desdeOutbox) {
      await SyncOutbox.instance.enqueueUpsert(
        entityType: 'producto',
        localId: productoId,
        forceBackground: forceBackground,
      );
    }
    if (!_puedeEscribirRemoto) {
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

      // Windows sync: NUNCA Storage aquí (putData/putFile tumba el .exe).
      // Fotos se sincronizan aparte / en Android.
      if (!PlatformCapabilities.isWindowsDesktop) {
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
              return;
            }
          }
        } catch (_) {}
      }

      // Hardening: jamás stock absoluto en upload de producto.
      await _remote.actualizarSinStock(producto);
      if (!desdeOutbox) {
        await SyncOutbox.instance.ack('upsert:producto:$productoId');
      }
    } catch (e) {
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
                !await SyncOutbox.instance.hasPendingLocalId('compra', id)) {
              await _reversoLocalAntesDeTombstone(
                documentType: 'compra',
                localId: id,
                stableDocumentId: numero,
                itemsTable: 'compra_items',
                fkColumn: 'compraId',
              );
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
          final codigo = item['productoCodigo']?.toString();
          final peerId = (item['productoId'] as num?)?.toInt();
          final productoId = await _productoLocalIdPorCodigo(db, codigo);
          if (productoId == null) {
            SyncPathLogger.instance.hop(
              stage: 'line_resolve',
              entityType: 'compra_item',
              entityId: numero,
              opId: 'pull:compra:$numero',
              eventId: 'pull:compra:$numero',
              outcome: 'skipped_missing_sku',
              extra: {'codigo': codigo, 'peerProductoId': peerId},
            );
            continue;
          }
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

  /// Lookup producto local por codigo. Nunca acepta id del peer.
  Future<int?> _productoLocalIdPorCodigo(
    DatabaseExecutor db,
    String? codigo,
  ) async {
    final cod = (codigo ?? '').trim();
    if (cod.isEmpty) return null;
    final prod = await db.query(
      'productos',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [cod],
      limit: 1,
    );
    if (prod.isEmpty) return null;
    return (prod.first['id'] as num?)?.toInt();
  }

  bool _reparandoTrasCatalogo = false;

  /// Tras llegar productos: stock_ops en hold + remitos/ventas/compras recientes.
  Future<void> _recuperarStockYDocsTrasCatalogo() async {
    if (_reparandoTrasCatalogo) return;
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    _reparandoTrasCatalogo = true;
    try {
      await _runStockOpsLane(() async {
        await _sweepStockOpsHolds(
          limit: PlatformCapabilities.isWindowsDesktop ? 40 : 80,
        );
        await _pullStockOpsRecientes(
          limit: PlatformCapabilities.isWindowsDesktop ? 40 : 120,
          maxApply: PlatformCapabilities.isWindowsDesktop
              ? WindowsSyncPolicy.stockOpsHardCap
              : 100,
        );
      });
      await _repararDocsComercialesTrasCatalogo();
    } catch (e) {
      debugPrint('recuperar stock/docs tras catálogo: $e');
    } finally {
      _reparandoTrasCatalogo = false;
    }
  }

  /// Completa líneas de docs que llegaron antes que el SKU local.
  Future<void> _repararDocsComercialesTrasCatalogo() async {
    try {
      final rem = await _remitosCol
          .orderBy('actualizadoEn', descending: true)
          .limit(40)
          .get();
      if (rem.docs.isNotEmpty) await _aplicarRemitosRemotos(rem);
    } catch (e) {
      debugPrint('reparar remitos tras catálogo: $e');
    }
    try {
      final ven = await _ventasCol
          .orderBy('actualizadoEn', descending: true)
          .limit(40)
          .get();
      if (ven.docs.isNotEmpty) await _aplicarVentasRemotas(ven);
    } catch (e) {
      debugPrint('reparar ventas tras catálogo: $e');
    }
    try {
      final com = await _comprasCol
          .orderBy('actualizadoEn', descending: true)
          .limit(40)
          .get();
      if (com.docs.isNotEmpty) await _aplicarComprasRemotas(com);
    } catch (e) {
      debugPrint('reparar compras tras catálogo: $e');
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
    final txId =
        'pull:remitos:${DateTime.now().toUtc().microsecondsSinceEpoch}';
    SyncPathLogger.instance.hop(
      stage: 'pull_snapshot',
      entityType: 'remito',
      eventId: txId,
      transactionId: txId,
      opId: txId,
      outcome: 'received',
      extra: {'docs': snap.docs.length},
    );
    try {
      var actual = snap;
      while (true) {
      final db = await DatabaseHelper.instance.database;
      final remoteNumeros = <String>{};
      var hubo = false;
      for (final doc in actual.docs) {
        final data = doc.data();
        final numero = data['numero']?.toString() ?? doc.id;
        final entityId = numero;
        final opId = 'pull:remito:$numero';
        if (isRemoteTombstone(data)) {
          // Tombstone remoto → reverso local si hace falta, luego borrar.
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
                !await SyncOutbox.instance.hasPendingLocalId('remito', id)) {
              await _reversoLocalAntesDeTombstone(
                documentType: 'remito',
                localId: id,
                stableDocumentId: numero,
                itemsTable: 'remito_items',
                fkColumn: 'remitoId',
              );
              await db.delete('remito_items',
                  where: 'remitoId = ?', whereArgs: [id]);
              await db.delete('remitos', where: 'id = ?', whereArgs: [id]);
              hubo = true;
              SyncPathLogger.instance.hop(
                stage: 'sqlite_delete',
                entityType: 'remito',
                eventId: opId,
                entityId: entityId,
                opId: opId,
                transactionId: txId,
                outcome: 'tombstone_applied',
              );
            }
          }
          _remitosConfirmadosEnNube.remove(numero);
          continue;
        }
        remoteNumeros.add(numero);
        SyncPathLogger.instance.hop(
          stage: 'firestore_doc',
          entityType: 'remito',
          eventId: opId,
          entityId: entityId,
          opId: opId,
          transactionId: txId,
          outcome: 'exists',
          extra: {
            'remoteDocId': doc.id,
            'items': ((data['items'] as List?) ?? const []).length,
            'peerProductoIds': ((data['items'] as List?) ?? const [])
                .map((raw) => (raw as Map)['productoId'])
                .toList(),
            'codigos': ((data['items'] as List?) ?? const [])
                .map((raw) => (raw as Map)['productoCodigo'])
                .toList(),
          },
        );
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
        SyncPathLogger.instance.hop(
          stage: 'sqlite_upsert_header',
          entityType: 'remito',
          eventId: opId,
          entityId: entityId,
          opId: opId,
          transactionId: txId,
          outcome: 'persisted',
          extra: {'localId': remitoId},
        );

        final items = (data['items'] as List?) ?? const [];
        var itemsOk = 0;
        var itemsSkippedMissingSku = 0;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final codigo = item['productoCodigo']?.toString();
          final peerId = (item['productoId'] as num?)?.toInt();
          final productoId = await _productoLocalIdPorCodigo(db, codigo);
          // Nunca usar peerId: con FK ON abortaba el apply del snapshot.
          if (productoId == null) {
            itemsSkippedMissingSku++;
            SyncPathLogger.instance.hop(
              stage: 'line_resolve',
              entityType: 'remito_item',
              eventId: opId,
              entityId: entityId,
              opId: opId,
              transactionId: txId,
              outcome: 'skipped_missing_sku',
              extra: {
                'codigo': codigo,
                'peerProductoId': peerId,
                'reason':
                    'productoCodigo no existe en SQLite local; peer id ignorado',
              },
            );
            continue;
          }

          await db.insert('remito_items', {
            'remitoId': remitoId,
            'productoId': productoId,
            'cantidad': item['cantidad'] ?? 0,
            'precio': item['precio'] ?? item['precioUnitario'] ?? 0,
            'subtotal': item['subtotal'] ?? 0,
            'costoUnitario': item['costoUnitario'] ?? 0,
            'ganancia': item['ganancia'] ?? 0,
          });
          itemsOk++;
        }
        SyncPathLogger.instance.hop(
          stage: 'sqlite_items',
          entityType: 'remito',
          eventId: opId,
          entityId: entityId,
          opId: opId,
          transactionId: txId,
          outcome: 'applied',
          extra: {
            'itemsOk': itemsOk,
            'itemsSkippedMissingSku': itemsSkippedMissingSku,
            'localId': remitoId,
          },
        );
        SyncObservabilityHub.instance.onRemoteApplied(
          entityType: 'remito',
          localId: remitoId,
          remoteId: doc.id,
        );
      }

      // Capacidad 7: solo tombstones borran locales (no inferir por ausencia).
      _remitosConfirmadosEnNube.addAll(remoteNumeros);
      await _persistirWatermarkRemitos();
      SyncPathLogger.instance.hop(
        stage: 'watermark',
        entityType: 'remito',
        eventId: txId,
        transactionId: txId,
        opId: txId,
        outcome: 'advanced',
        extra: {'numeros': remoteNumeros.length},
      );

      if (hubo) {
        // C7: CC local desde saldos de docs remotos (ventas día/mes + saldo).
        final clienteIds = <int>{};
        for (final doc in actual.docs) {
          final data = doc.data();
          if (isRemoteTombstone(data)) continue;
          final numero = data['numero']?.toString() ?? doc.id;
          final rows = await db.query(
            'remitos',
            columns: ['clienteId'],
            where: 'numero = ?',
            whereArgs: [numero],
            limit: 1,
          );
          final cid = (rows.isEmpty
                  ? null
                  : (rows.first['clienteId'] as num?)?.toInt());
          if (cid != null) clienteIds.add(cid);
        }
        for (final cid in clienteIds) {
          try {
            await CuentaCorrienteService().recalcularSaldoCliente(cid);
          } catch (e) {
            debugPrint('CC recalc remito remoto $cid: $e');
          }
        }
        // Inicio KPI (ventas día/mes) suma remitos — refrescar al llegar del PC.
        DataRefreshHub.instance.notifyVentas();
        DataRefreshHub.instance.notifyTodo();
        SyncPathLogger.instance.hop(
          stage: 'ui_notify',
          entityType: 'remito',
          eventId: txId,
          transactionId: txId,
          opId: txId,
          outcome: 'DataRefreshHub.notifyVentas+notifyTodo',
        );
      }
      final pendiente = _snapRemitosPendiente;
      _snapRemitosPendiente = null;
      if (pendiente == null) break;
      actual = pendiente;
      }
    } catch (e, st) {
      // No ocultar: registrar SQL/exception exacta y rethrow implícito vía log.
      SyncPathLogger.instance.hop(
        stage: 'apply_abort',
        entityType: 'remito',
        eventId: txId,
        transactionId: txId,
        opId: txId,
        outcome: 'FAILED',
        extra: {
          'error': e.toString(),
          'stack': st.toString().split('\n').take(12).join(' | '),
        },
      );
      debugPrint('Aplicar remitos remotos: $e\n$st');
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
                  !await SyncOutbox.instance.hasPendingLocalId('venta', id)) {
                await _reversoLocalAntesDeTombstone(
                  documentType: 'venta',
                  localId: id,
                  stableDocumentId: numero,
                  itemsTable: 'ventas_items',
                  fkColumn: 'ventaId',
                );
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
            final codigo = item['productoCodigo']?.toString();
            final peerId = (item['productoId'] as num?)?.toInt();
            final productoId = await _productoLocalIdPorCodigo(db, codigo);
            // Si el producto no existe aún en este nodo: omitir línea (no peer id).
            if (productoId == null) {
              SyncPathLogger.instance.hop(
                stage: 'line_resolve',
                entityType: 'venta_item',
                entityId: numero,
                opId: 'pull:venta:$numero',
                eventId: 'pull:venta:$numero',
                outcome: 'skipped_missing_sku',
                extra: {'codigo': codigo, 'peerProductoId': peerId},
              );
              continue;
            }

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
          try {
            SyncObservabilityHub.instance.onRemoteApplied(
              entityType: 'venta',
              localId: ventaId,
              remoteId: doc.id,
            );
          } catch (_) {}
        } catch (e) {
          debugPrint('Aplicar venta remota ${doc.id}: $e');
        }
      }
      if (huboCambios) {
        // C7: alinear saldo CC con docs remotos aplicados.
        final clienteIds = <int>{};
        for (final doc in actual.docs) {
          try {
            final data = doc.data();
            if (isRemoteTombstone(data)) continue;
            final numero = data['numero']?.toString() ?? doc.id;
            if (numero.isEmpty) continue;
            final rows = await db.query(
              'ventas',
              columns: ['clienteId'],
              where: 'numero = ?',
              whereArgs: [numero],
              limit: 1,
            );
            final cid = (rows.isEmpty
                    ? null
                    : (rows.first['clienteId'] as num?)?.toInt());
            if (cid != null) clienteIds.add(cid);
          } catch (_) {}
        }
        for (final cid in clienteIds) {
          try {
            await CuentaCorrienteService().recalcularSaldoCliente(cid);
          } catch (e) {
            debugPrint('CC recalc venta remota $cid: $e');
          }
        }
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
        final codigosTocados = <String>{};
        for (final producto in actual) {
          final local =
              await _cache.buscarPorCodigoIncluyendoEliminados(producto.codigo);

          // Hard-delete remoto (tombstone): borrar fila local, no soft-delete.
          if (producto.esTombstoneRemoto) {
            final localId = local?.id;
            if (localId != null &&
                !await SyncOutbox.instance
                    .hasPendingLocalId('producto', localId)) {
              huboCambios = true;
              batch.delete(
                'productos',
                where: 'id = ?',
                whereArgs: [localId],
              );
            }
            continue;
          }

          final locTs = _parseUtc(local?.actualizadoEn);
          final remTs = _parseUtc(producto.actualizadoEn);

          // Soft-delete/restore es independiente del LWW de catálogo.
          // stock_ops (antes) y edits locales bumpaban actualizadoEn y
          // bloqueaban deleted_at remoto → totales 2884 vs 2883.
          if (local != null &&
              producto.estaEliminado != local.estaEliminado) {
            huboCambios = true;
            batch.update(
              'productos',
              {
                'deleted_at':
                    producto.estaEliminado ? producto.deletedAt : null,
              },
              where: 'id = ?',
              whereArgs: [local.id],
            );
            // Seguir: si local es más viejo también mergeamos metadata.
          }

          // R6/R7: stock local (ledger / stock_ops) es autoridad.
          // Nunca sobrescribir proyección local con stock absoluto remoto.
          if (local != null &&
              locTs != null &&
              remTs != null &&
              locTs.isAfter(remTs)) {
            // Metadata local más nueva: no tocar stock ni pisar fila.
            continue;
          }

          var merged = _fusionarProductoRemoto(producto, local);
          if (producto.estaEliminado) {
            merged = merged.copyWith(deletedAt: producto.deletedAt);
          } else if (local?.estaEliminado == true) {
            merged = merged.copyWith(clearDeletedAt: true);
          }
          // Producto existente: conservar stock local (fuente = ledger).
          // Producto nuevo: semilla 0 — stock_ops construyen la proyección
          // (semilla = stock remoto absoluto duplicaba deltas → diverge EXE↔APK).
          if (local != null) {
            merged = merged.copyWith(stock: local.stock);
          } else {
            merged = merged.copyWith(stock: 0);
          }
          if (local != null && _productoSinCambiosRelevantes(local, merged)) {
            continue;
          }
          // Si hay ops/outbox pendientes del producto, no pisar metadata stock.
          if (local?.id != null &&
              await SyncOutbox.instance
                  .hasPendingLocalId('producto', local!.id!)) {
            continue;
          }
          huboCambios = true;
          codigosTocados.add(producto.codigo.trim());
          final data = merged.toMap();
          data['actualizadoEn'] = producto.actualizadoEn ??
              merged.actualizadoEn ??
              DateTime.now().toUtc().toIso8601String();
          if (local?.id != null) {
            // Nunca escribir stock absoluto en update de sync metadata.
            data.remove('stock');
            batch.update(
              'productos',
              data..remove('id'),
              where: 'id = ?',
              whereArgs: [local!.id],
            );
          } else {
            final dataNew = Map<String, dynamic>.from(data)..remove('id');
            dataNew['stock'] = 0;
            batch.insert(
              'productos',
              dataNew,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        if (huboCambios) {
          await batch.commit(noResult: true);
          DataRefreshHub.instance.notifyProductos();
          DataRefreshHub.instance.notifyStock();
          // Stock: liberar holds de SKUs que acabaron de llegar y aplicar.
          for (final cod in codigosTocados) {
            if (cod.isEmpty) continue;
            try {
              await StockOpsPullHoldStore.instance.forceDueForCodigo(cod);
            } catch (_) {}
          }
          unawaited(_recuperarStockYDocsTrasCatalogo());
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
    var actual = producto;
    // Windows: no tocar Storage desde sync/alta (putData tumba el .exe).
    if (!PlatformCapabilities.isWindowsDesktop) {
      final sincronizado =
          await MediaSyncService.instance.sincronizarFotosProducto(
        producto.codigo,
        producto.todasLasFotos,
      );
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
        // Soft-delete: metadata only — never merge absolute stock.
        await remote.actualizarSinStock(producto);
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
