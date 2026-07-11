import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../../firebase_options.dart';
import '../../models/comentario_interno.dart';
import '../../models/documento_cliente.dart';
import '../../models/venta.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../config/backend_config_service.dart';
import 'firestore_sync_service.dart';

/// Estados visibles para el indicador de sincronización.
enum SyncUiStatus {
  sincronizado,
  pendiente,
  sinConexion,
  error,
  procesando,
}

/// Cola persistente de operaciones outbound hacia Firestore.
///
/// No reemplaza [FirestoreSyncService]: solo garantiza que los `subir*` /
/// `eliminar*` no se pierdan si no hay red o Auth, con reintentos.
class SyncQueueService extends ChangeNotifier {
  SyncQueueService._();
  static final SyncQueueService instance = SyncQueueService._();

  static const _maxAttempts = 8;
  static const _batchSize = 12;

  Timer? _timer;
  bool _running = false;
  bool _processing = false;

  int pendingCount = 0;
  int failedCount = 0;
  bool isProcessing = false;
  bool _offlineHint = false;
  String? lastError;
  DateTime? lastSuccessAt;

  bool get puedeEscribirRemoto {
    return BackendConfigService.instance.firebaseEnabled &&
        FirebaseBootstrap.isReady &&
        FirebaseAuthUsuarioService.instance.uidActual != null;
  }

  SyncUiStatus get uiStatus {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady ||
        FirebaseAuthUsuarioService.instance.uidActual == null ||
        _offlineHint) {
      return SyncUiStatus.sinConexion;
    }
    if (isProcessing) return SyncUiStatus.procesando;
    if (failedCount > 0) return SyncUiStatus.error;
    if (pendingCount > 0) return SyncUiStatus.pendiente;
    return SyncUiStatus.sincronizado;
  }

  String get uiLabel {
    switch (uiStatus) {
      case SyncUiStatus.sincronizado:
        return 'Sincronizado';
      case SyncUiStatus.pendiente:
        return 'Pendiente ($pendingCount)';
      case SyncUiStatus.sinConexion:
        if (!BackendConfigService.instance.firebaseEnabled ||
            !FirebaseBootstrap.isReady) {
          return 'Firebase no listo';
        }
        if (FirebaseAuthUsuarioService.instance.uidActual == null) {
          return pendingCount > 0
              ? 'Sin sesión nube ($pendingCount)'
              : 'Sin sesión nube';
        }
        return pendingCount > 0
            ? 'Sin conexión ($pendingCount)'
            : 'Sin conexión';
      case SyncUiStatus.error:
        return 'Error de sync ($failedCount)';
      case SyncUiStatus.procesando:
        return 'Sincronizando…';
    }
  }

  /// Texto largo para tooltip / diagnóstico.
  String get uiDetalle {
    if (!DefaultFirebaseOptions.isConfigured) {
      return 'Faltan credenciales Firebase en la app.';
    }
    if (!BackendConfigService.instance.firebaseEnabled) {
      return 'Firebase está deshabilitado en configuración.';
    }
    if (!FirebaseBootstrap.isReady) {
      return 'Firebase no inicializó en este dispositivo. Revisá internet y reiniciá la app.';
    }
    if (FirebaseAuthUsuarioService.instance.uidActual == null) {
      if (lastError?.isNotEmpty == true) return lastError!;
      return 'Entraste solo en modo local. Tocá "Conectar a la nube" e ingresá '
          'tu contraseña. En Firebase Console debe estar activo '
          'Authentication → Correo/contraseña.';
    }
    if (lastError?.isNotEmpty == true) return lastError!;
    if (pendingCount > 0) {
      return 'Hay $pendingCount operación(es) pendientes de subir.';
    }
    return 'Conectado a la nube. Los cambios se comparten entre dispositivos.';
  }

  void reportAuthError(String? message) {
    lastError = message;
    _notifySafe();
  }

  void clearAuthError() {
    lastError = null;
    _notifySafe();
  }

  void _notifySafe() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> start() async {
    _running = true;
    await refreshCounts();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(processQueue());
    });
    unawaited(processQueue());
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Encola una operación. Si ya existe el mismo [dedupeKey], la reinicia a pending.
  Future<void> enqueue({
    required String entityType,
    required String operation,
    required String entityId,
    String? payloadJson,
    bool processNow = true,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final dedupeKey = '$entityType:$entityId:$operation';
    final db = await DatabaseHelper.instance.database;

    await db.insert(
      'sync_queue',
      {
        'entityType': entityType,
        'operation': operation,
        'entityId': entityId,
        'payloadJson': payloadJson ?? '',
        'dedupeKey': dedupeKey,
        'status': 'pending',
        'attempts': 0,
        'lastError': '',
        'createdAt': now,
        'updatedAt': now,
        'nextRetryAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await refreshCounts();
    if (processNow) unawaited(processQueue());
  }

  Future<void> enqueueUpsert(String entityType, int id) => enqueue(
        entityType: entityType,
        operation: 'upsert',
        entityId: '$id',
      );

  Future<void> enqueueDelete({
    required String entityType,
    required String entityId,
    String? payloadJson,
  }) =>
      enqueue(
        entityType: entityType,
        operation: 'delete',
        entityId: entityId,
        payloadJson: payloadJson,
      );

  /// Intenta subir ahora; si no hay remoto o falla, encola de forma persistente.
  Future<void> pushOrEnqueue({
    required String entityType,
    required String entityId,
    required Future<void> Function() upload,
    String operation = 'upsert',
    String? payloadJson,
  }) async {
    if (puedeEscribirRemoto) {
      try {
        await FirestoreSyncService.instance.runOutboundStrict(upload);
        _offlineHint = false;
        return;
      } catch (e) {
        _offlineHint = _pareceSinRed(e);
        debugPrint('Sync pushOrEnqueue → cola ($entityType/$entityId): $e');
      }
    } else {
      _offlineHint = true;
    }
    await enqueue(
      entityType: entityType,
      operation: operation,
      entityId: entityId,
      payloadJson: payloadJson,
    );
  }

  Future<void> pushOrEnqueueUpsert({
    required String entityType,
    required int id,
    required Future<void> Function() upload,
  }) =>
      pushOrEnqueue(
        entityType: entityType,
        entityId: '$id',
        upload: upload,
      );

  bool _pareceSinRed(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('unavailable') ||
        s.contains('offline') ||
        s.contains('connection') ||
        s.contains('timed out') ||
        s.contains('timeout');
  }

  Future<void> refreshCounts() async {
    final db = await DatabaseHelper.instance.database;
    final pending = await db.rawQuery(
      "SELECT COUNT(*) c FROM sync_queue WHERE status IN ('pending','processing')",
    );
    final failed = await db.rawQuery(
      "SELECT COUNT(*) c FROM sync_queue WHERE status = 'failed'",
    );
    pendingCount = Sqflite.firstIntValue(pending) ?? 0;
    failedCount = Sqflite.firstIntValue(failed) ?? 0;
    _notifySafe();
  }

  Future<void> processQueue() async {
    if (!_running || _processing) return;
    if (!puedeEscribirRemoto) {
      await refreshCounts();
      return;
    }

    _processing = true;
    isProcessing = true;
    _notifySafe();

    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await db.query(
        'sync_queue',
        where: "status IN ('pending','failed') AND "
            "(nextRetryAt IS NULL OR nextRetryAt <= ?)",
        whereArgs: [now],
        orderBy: 'id ASC',
        limit: _batchSize,
      );

      for (final row in rows) {
        await _processRow(db, row);
      }
    } catch (e, st) {
      lastError = e.toString();
      debugPrint('SyncQueue process: $e\n$st');
    } finally {
      _processing = false;
      isProcessing = false;
      await refreshCounts();
    }
  }

  /// Reencola ítems fallidos para reintento inmediato.
  Future<void> reintentarFallidos() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'sync_queue',
      {'status': 'pending', 'nextRetryAt': now, 'updatedAt': now},
      where: "status = 'failed'",
    );
    await refreshCounts();
    await processQueue();
  }

  Future<List<Map<String, dynamic>>> listarCola({int limit = 100}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'sync_queue',
      where: "status != 'done'",
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> listarHistorial({int limit = 100}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'sync_history',
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<void> _processRow(Database db, Map<String, dynamic> row) async {
    final id = row['id'] as int;
    final entityType = row['entityType']?.toString() ?? '';
    final operation = row['operation']?.toString() ?? '';
    final entityId = row['entityId']?.toString() ?? '';
    final payloadJson = row['payloadJson']?.toString() ?? '';
    final attempts = (row['attempts'] as int?) ?? 0;
    final started = DateTime.now();

    await db.update(
      'sync_queue',
      {
        'status': 'processing',
        'updatedAt': started.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    try {
      await _dispatch(
        entityType: entityType,
        operation: operation,
        entityId: entityId,
        payloadJson: payloadJson,
      );

      final finished = DateTime.now();
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
      await db.insert('sync_history', {
        'queueId': id,
        'entityType': entityType,
        'operation': operation,
        'entityId': entityId,
        'status': 'success',
        'error': '',
        'durationMs': finished.difference(started).inMilliseconds,
        'finishedAt': finished.toUtc().toIso8601String(),
      });
      lastSuccessAt = finished;
      lastError = null;
      _offlineHint = false;
    } catch (e) {
      _offlineHint = _pareceSinRed(e);
      final nextAttempts = attempts + 1;
      final finished = DateTime.now();
      final backoffSec = _backoffSeconds(nextAttempts);
      final nextRetry =
          finished.add(Duration(seconds: backoffSec)).toUtc().toIso8601String();
      final failedPermanently = nextAttempts >= _maxAttempts;

      await db.update(
        'sync_queue',
        {
          'status': failedPermanently ? 'failed' : 'pending',
          'attempts': nextAttempts,
          'lastError': e.toString(),
          'updatedAt': finished.toUtc().toIso8601String(),
          'nextRetryAt': nextRetry,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await db.insert('sync_history', {
        'queueId': id,
        'entityType': entityType,
        'operation': operation,
        'entityId': entityId,
        'status': failedPermanently ? 'failed' : 'retry',
        'error': e.toString(),
        'durationMs': finished.difference(started).inMilliseconds,
        'finishedAt': finished.toUtc().toIso8601String(),
      });

      lastError = e.toString();
      debugPrint('SyncQueue fail $entityType/$entityId: $e');
    }
  }

  int _backoffSeconds(int attempts) {
    // 5s, 10s, 20s, 40s... capped at 15 min
    final sec = 5 * (1 << (attempts - 1).clamp(0, 8));
    return sec.clamp(5, 900);
  }

  Future<void> _dispatch({
    required String entityType,
    required String operation,
    required String entityId,
    required String payloadJson,
  }) async {
    final sync = FirestoreSyncService.instance;

    if (!puedeEscribirRemoto) {
      throw StateError('Sin sesión Firebase / sin conexión remota');
    }

    await sync.runOutboundStrict(() async {
      switch (entityType) {
        case 'cliente':
          if (operation == 'delete') {
            final syncId = _payloadString(payloadJson, 'syncId') ?? entityId;
            await sync.eliminarClienteRemoto(syncId);
          } else {
            await sync.subirCliente(int.parse(entityId));
          }
          return;
        case 'proveedor':
          if (operation == 'delete') {
            final syncId = _payloadString(payloadJson, 'syncId') ?? entityId;
            await sync.eliminarProveedorRemoto(syncId);
          } else {
            await sync.subirProveedor(int.parse(entityId));
          }
          return;
        case 'producto':
          await sync.subirProductoPorId(int.parse(entityId));
          return;
        case 'venta':
          if (operation == 'delete') {
            final map = _decodeMap(payloadJson);
            final venta = Venta.fromMap({
              'id': int.tryParse(entityId),
              'numero': map['numero'] ?? '',
              ...map,
            });
            await sync.eliminarVentaRemota(venta);
          } else {
            await sync.subirVenta(int.parse(entityId));
          }
          return;
        case 'remito':
          await sync.subirRemito(int.parse(entityId));
          return;
        case 'compra':
          await sync.subirCompra(int.parse(entityId));
          return;
        case 'documento':
          final map = _decodeMap(payloadJson);
          if (map.isEmpty) {
            throw StateError('Documento sin payload');
          }
          await sync.subirDocumento(DocumentoCliente.fromMap(map));
          return;
        case 'categoria':
          if (operation == 'delete') {
            final nombre =
                _payloadString(payloadJson, 'nombre') ?? entityId;
            await sync.eliminarCategoriaRemota(nombre);
          } else {
            await sync.subirCategoria(int.parse(entityId));
          }
          return;
        case 'lista_precio':
          if (operation == 'delete') {
            final nombre =
                _payloadString(payloadJson, 'nombre') ?? entityId;
            await sync.eliminarListaPrecioRemota(nombre);
          } else {
            await sync.subirListaPrecio(int.parse(entityId));
          }
          return;
        case 'comentario':
          final map = _decodeMap(payloadJson);
          if (map.isEmpty) {
            throw StateError('Comentario sin payload');
          }
          final c = ComentarioInterno.fromMap(map);
          if (operation == 'delete') {
            await sync.eliminarComentarioRemoto(c);
          } else {
            await sync.subirComentario(c);
          }
          return;
        default:
          throw StateError('entityType desconocido: $entityType');
      }
    });
  }

  Map<String, dynamic> _decodeMap(String raw) {
    if (raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }

  String? _payloadString(String raw, String key) {
    final map = _decodeMap(raw);
    final v = map[key]?.toString();
    if (v == null || v.isEmpty) return null;
    return v;
  }
}
