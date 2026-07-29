import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'observability/sync_observability_hub.dart';
import 'scheduler/sync_priority.dart';
import 'scheduler/sync_scheduler_metrics.dart';
import '../../database/database_helper.dart';

/// Estados del outbox (Capacidad 2).
class SyncOutboxStatus {
  static const pending = 'pending';
  static const inflight = 'inflight';
  static const acked = 'acked';
  static const dead = 'dead';
}

class SyncOutboxOp {
  SyncOutboxOp({
    required this.opId,
    required this.entityType,
    required this.operation,
    this.entityLocalId,
    this.entityRemoteId,
    this.payloadJson,
    this.status = SyncOutboxStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    int? priority,
    SyncLane? lane,
    this.coalesceKey,
  })  : priority = priority ?? SyncPriority.forEntityType(entityType),
        lane = lane ?? SyncLane.forEntityType(entityType);

  final String opId;
  final String entityType;
  final String operation; // upsert | delete
  final int? entityLocalId;
  final String? entityRemoteId;
  final String? payloadJson;
  final String status;
  final int attempts;
  final String? lastError;
  final String? nextAttemptAt;
  final int priority;
  final SyncLane lane;
  final String? coalesceKey;

  Map<String, dynamic> toInsertMap() {
    final ahora = DateTime.now().toUtc().toIso8601String();
    return {
      'op_id': opId,
      'entity_type': entityType,
      'entity_local_id': entityLocalId,
      'entity_remote_id': entityRemoteId,
      'operation': operation,
      'payload': payloadJson,
      'status': status,
      'attempts': attempts,
      'last_error': lastError,
      'created_at': ahora,
      'updated_at': ahora,
      'next_attempt_at': nextAttemptAt,
      'priority': priority,
      'lane': lane.wireName,
      'coalesce_key': coalesceKey,
    };
  }
}

/// Cola durable con ACK explícito. No se borra hasta confirmar remoto.
class SyncOutbox {
  SyncOutbox._();
  static final SyncOutbox instance = SyncOutbox._();

  static const maxAttempts = 12;

  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// Encola upsert. Idempotente por opId estable (coalesce natural).
  ///
  /// [reopenAcked]: `true` (default) ante edición real del usuario.
  /// `false` al absorber colas legacy / catch-up — no reabre lo ya sincronizado
  /// (evita "N pendientes" fantasma al login en Windows).
  ///
  /// [forceBackground]: importaciones / masivos → lane fondo, prioridad baja.
  Future<void> enqueueUpsert({
    required String entityType,
    required int localId,
    String? remoteId,
    Map<String, dynamic>? payload,
    bool reopenAcked = true,
    bool forceBackground = false,
  }) async {
    final opId = 'upsert:$entityType:$localId';
    final priority = forceBackground
        ? SyncPriority.background
        : SyncPriority.forEntityType(entityType);
    final lane = forceBackground
        ? SyncLane.background
        : SyncLane.forEntityType(entityType);
    final coalesceKey =
        SyncPriority.canCoalesce(entityType, 'upsert') ? opId : null;
    await _upsertPending(
      SyncOutboxOp(
        opId: opId,
        entityType: entityType,
        operation: 'upsert',
        entityLocalId: localId,
        entityRemoteId: remoteId,
        payloadJson: payload == null ? null : jsonEncode(payload),
        priority: priority,
        lane: lane,
        coalesceKey: coalesceKey,
      ),
      reopenAcked: reopenAcked,
    );
  }

  Future<void> enqueueDelete({
    required String entityType,
    String? remoteId,
    int? localId,
    Map<String, dynamic>? payload,
  }) async {
    final key = remoteId?.isNotEmpty == true
        ? remoteId!
        : (localId?.toString() ?? const Uuid().v4());
    final opId = 'delete:$entityType:$key';
    await _upsertPending(
      SyncOutboxOp(
        opId: opId,
        entityType: entityType,
        operation: 'delete',
        entityLocalId: localId,
        entityRemoteId: remoteId,
        payloadJson: payload == null ? null : jsonEncode(payload),
        priority: SyncPriority.forEntityType(entityType),
        lane: SyncLane.forEntityType(entityType),
      ),
    );
  }

  /// Stock op durable (Capacidad 7). No usa prefs: sobrevive kill mid-flush.
  Future<void> enqueueStockOp({
    required String opId,
    required String codigo,
    required int delta,
    String? documentType,
    String? documentId,
  }) async {
    if (opId.isEmpty || codigo.isEmpty || delta == 0) return;
    final db = await _db;
    await enqueueStockOpInTxn(
      db,
      opId: opId,
      codigo: codigo,
      delta: delta,
      documentType: documentType,
      documentId: documentId,
    );
  }

  /// Encola stock_op dentro de una TX SQLite existente (ledger + outbox atómicos).
  Future<void> enqueueStockOpInTxn(
    DatabaseExecutor txn, {
    required String opId,
    required String codigo,
    required int delta,
    String? documentType,
    String? documentId,
  }) async {
    if (opId.isEmpty || codigo.isEmpty || delta == 0) return;
    final payload = <String, dynamic>{
      'opId': opId,
      'codigo': codigo,
      'delta': delta,
    };
    final dt = (documentType ?? '').trim();
    final di = (documentId ?? '').trim();
    if (dt.isNotEmpty) payload['documentType'] = dt;
    if (di.isNotEmpty) payload['documentId'] = di;
    await _upsertPendingOn(
      txn,
      SyncOutboxOp(
        opId: 'stock_op:$opId',
        entityType: 'stock_op',
        operation: 'upsert',
        entityRemoteId: opId,
        payloadJson: jsonEncode(payload),
        priority: SyncPriority.critical,
        lane: SyncLane.critical,
      ),
    );
  }

  /// ¿Hay delete pendiente/inflight para este remoteId?
  Future<bool> hasPendingDelete({
    required String entityType,
    required String remoteId,
  }) async {
    if (remoteId.isEmpty) return false;
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['id'],
      where:
          "entity_type = ? AND entity_remote_id = ? AND operation = ? AND status IN (?, ?)",
      whereArgs: [
        entityType,
        remoteId,
        'delete',
        SyncOutboxStatus.pending,
        SyncOutboxStatus.inflight,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _upsertPending(
    SyncOutboxOp op, {
    bool reopenAcked = true,
  }) async {
    final db = await _db;
    await _upsertPendingOn(db, op, reopenAcked: reopenAcked);
  }

  Future<void> _upsertPendingOn(
    DatabaseExecutor db,
    SyncOutboxOp op, {
    bool reopenAcked = true,
  }) async {
    final existing = await db.query(
      'sync_outbox',
      where: 'op_id = ?',
      whereArgs: [op.opId],
      limit: 1,
    );
    final ahora = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('sync_outbox', op.toInsertMap());
      try {
        SyncObservabilityHub.instance.onEnqueue(
          opId: op.opId,
          entityType: op.entityType,
          localId: op.entityLocalId,
          remoteId: op.entityRemoteId,
        );
      } catch (_) {}
      return;
    }
    final status = existing.first['status']?.toString() ?? '';
    // Coalesce: mismo opId upsertable → actualizar payload (último gana).
    final coalescing = SyncPriority.canCoalesce(op.entityType, op.operation) &&
        (status == SyncOutboxStatus.pending ||
            status == SyncOutboxStatus.inflight ||
            status == SyncOutboxStatus.acked);
    if (coalescing && status != SyncOutboxStatus.acked) {
      SyncSchedulerMetrics.instance.recordCoalesce();
    }
    if (status == SyncOutboxStatus.acked) {
      if (!reopenAcked) return;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'payload': op.payloadJson,
          'entity_local_id': op.entityLocalId,
          'entity_remote_id': op.entityRemoteId,
          'priority': op.priority,
          'lane': op.lane.wireName,
          'attempts': 0,
          'last_error': null,
          'updated_at': ahora,
          'next_attempt_at': null,
        },
        where: 'op_id = ?',
        whereArgs: [op.opId],
      );
      return;
    }
    if (status == SyncOutboxStatus.pending ||
        status == SyncOutboxStatus.inflight) {
      await db.update(
        'sync_outbox',
        {
          'payload': op.payloadJson,
          'entity_local_id': op.entityLocalId,
          'entity_remote_id': op.entityRemoteId,
          'priority': op.priority,
          'lane': op.lane.wireName,
          'updated_at': ahora,
        },
        where: 'op_id = ?',
        whereArgs: [op.opId],
      );
      return;
    }
    // dead u otro: reabrir a pending.
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'payload': op.payloadJson,
        'entity_local_id': op.entityLocalId,
        'entity_remote_id': op.entityRemoteId,
        'priority': op.priority,
        'lane': op.lane.wireName,
        'attempts': 0,
        'last_error': null,
        'updated_at': ahora,
        'next_attempt_at': null,
      },
      where: 'op_id = ?',
      whereArgs: [op.opId],
    );
  }

  /// Inflight viejos → pending (crash / corte de luz).
  /// Si ya superó [maxAttempts], pasa a `dead` (corta bucles eternos de reclaim).
  Future<int> reclaimStaleInflight({
    Duration olderThan = const Duration(minutes: 5),
  }) async {
    final db = await _db;
    final cutoff =
        DateTime.now().toUtc().subtract(olderThan).toIso8601String();
    final ahora = DateTime.now().toUtc().toIso8601String();
    final stale = await db.query(
      'sync_outbox',
      columns: ['op_id', 'attempts'],
      where: 'status = ? AND updated_at < ?',
      whereArgs: [SyncOutboxStatus.inflight, cutoff],
    );
    var n = 0;
    for (final row in stale) {
      final opId = row['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final attempts = (row['attempts'] as num?)?.toInt() ?? 0;
      if (attempts >= maxAttempts) {
        n += await db.update(
          'sync_outbox',
          {
            'status': SyncOutboxStatus.dead,
            'updated_at': ahora,
            'last_error': 'reclaimed_stale_inflight_max_attempts',
            'next_attempt_at': null,
          },
          where: 'op_id = ? AND status = ?',
          whereArgs: [opId, SyncOutboxStatus.inflight],
        );
      } else {
        n += await db.update(
          'sync_outbox',
          {
            'status': SyncOutboxStatus.pending,
            'updated_at': ahora,
            'last_error': 'reclaimed_stale_inflight',
            // Backoff: no reclamar en el mismo segundo.
            'next_attempt_at': DateTime.now()
                .toUtc()
                .add(Duration(seconds: (1 << attempts.clamp(0, 6)).clamp(2, 128)))
                .toIso8601String(),
          },
          where: 'op_id = ? AND status = ?',
          whereArgs: [opId, SyncOutboxStatus.inflight],
        );
      }
    }
    return n;
  }

  /// Claim: por defecto ordena por prioridad (crítico primero).
  Future<List<Map<String, dynamic>>> claimBatch({
    int limit = 40,
    List<String>? entityTypes,
    bool orderByPriority = true,
    String? lane,
  }) async {
    final db = await _db;
    final ahora = DateTime.now().toUtc().toIso8601String();
    var where =
        "status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)";
    final whereArgs = <Object>[SyncOutboxStatus.pending, ahora];
    if (entityTypes != null && entityTypes.isNotEmpty) {
      final placeholders = List.filled(entityTypes.length, '?').join(',');
      where += ' AND entity_type IN ($placeholders)';
      whereArgs.addAll(entityTypes);
    }
    if (lane != null && lane.isNotEmpty) {
      where += ' AND lane = ?';
      whereArgs.add(lane);
    }
    final orderBy = orderByPriority
        ? 'priority ASC, id ASC'
        : 'id ASC';
    final rows = await db.query(
      'sync_outbox',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    final claimed = <Map<String, dynamic>>[];
    for (final row in rows) {
      final opId = row['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final n = await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.inflight,
          'updated_at': ahora,
          'attempts': ((row['attempts'] as num?)?.toInt() ?? 0) + 1,
        },
        where: 'op_id = ? AND status = ?',
        whereArgs: [opId, SyncOutboxStatus.pending],
      );
      if (n > 0) {
        claimed.add(Map<String, dynamic>.from(row)
          ..['status'] = SyncOutboxStatus.inflight
          ..['attempts'] = ((row['attempts'] as num?)?.toInt() ?? 0) + 1);
        try {
          SyncObservabilityHub.instance.onClaimed(opId);
        } catch (_) {}
      }
    }
    return claimed;
  }

  Future<void> ack(String opId) async {
    final db = await _db;
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.acked,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
        'next_attempt_at': null,
      },
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<void> fail(String opId, Object error) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final status = rows.first['status']?.toString() ?? '';
    // No pisar un ACK concurrente (interactive vs pump).
    if (status != SyncOutboxStatus.pending &&
        status != SyncOutboxStatus.inflight) {
      return;
    }
    final attempts = (rows.first['attempts'] as num?)?.toInt() ?? 1;
    final dead = attempts >= maxAttempts;
    final backoffSec = (1 << (attempts.clamp(0, 6))).clamp(2, 128);
    final next = DateTime.now()
        .toUtc()
        .add(Duration(seconds: backoffSec))
        .toIso8601String();
    await db.update(
      'sync_outbox',
      {
        'status': dead ? SyncOutboxStatus.dead : SyncOutboxStatus.pending,
        'last_error': error.toString().length > 500
            ? error.toString().substring(0, 500)
            : error.toString(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'next_attempt_at': dead ? null : next,
      },
      where: 'op_id = ? AND status IN (?, ?)',
      whereArgs: [
        opId,
        SyncOutboxStatus.pending,
        SyncOutboxStatus.inflight,
      ],
    );
  }

  /// Reencola inmediato sin backoff (preemption Turbo → L1).
  /// Decrementa attempts para no castigar ops interrumpidas.
  Future<void> requeueImmediate(String opId, {String reason = 'preempted'}) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['attempts'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final attempts = (rows.first['attempts'] as num?)?.toInt() ?? 1;
    await db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'attempts': (attempts - 1).clamp(0, maxAttempts),
        'last_error': reason,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'next_attempt_at': null,
      },
      where: 'op_id = ? AND status IN (?, ?)',
      whereArgs: [
        opId,
        SyncOutboxStatus.pending,
        SyncOutboxStatus.inflight,
      ],
    );
  }

  Future<int> countByStatus(String status) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM sync_outbox WHERE status = ?',
      [status],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, int>> counts() async {
    return {
      SyncOutboxStatus.pending: await countByStatus(SyncOutboxStatus.pending),
      SyncOutboxStatus.inflight: await countByStatus(SyncOutboxStatus.inflight),
      SyncOutboxStatus.acked: await countByStatus(SyncOutboxStatus.acked),
      SyncOutboxStatus.dead: await countByStatus(SyncOutboxStatus.dead),
    };
  }

  /// Conteo de pendientes/inflight por tipo (para UI: "producto×8, remito×1").
  Future<Map<String, int>> pendingBreakdown() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
SELECT entity_type AS t, COUNT(*) AS c
FROM sync_outbox
WHERE status IN (?, ?)
GROUP BY entity_type
ORDER BY c DESC
''',
      [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
    );
    final out = <String, int>{};
    for (final r in rows) {
      final t = r['t']?.toString() ?? '';
      if (t.isEmpty) continue;
      out[t] = (r['c'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  /// Pendientes por carril (scheduler observability).
  Future<Map<String, int>> pendingByLane() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
SELECT COALESCE(lane, 'background') AS l, COUNT(*) AS c
FROM sync_outbox
WHERE status IN (?, ?)
GROUP BY l
''',
      [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
    );
    final out = <String, int>{
      SyncLane.critical.wireName: 0,
      SyncLane.high.wireName: 0,
      SyncLane.normal.wireName: 0,
      SyncLane.background.wireName: 0,
    };
    for (final r in rows) {
      final l = r['l']?.toString() ?? SyncLane.background.wireName;
      out[l] = (out[l] ?? 0) + ((r['c'] as num?)?.toInt() ?? 0);
    }
    return out;
  }

  /// Muestra legible del desglose (máx ~3 tipos).
  static String formatBreakdown(Map<String, int> breakdown, {int maxTypes = 4}) {
    if (breakdown.isEmpty) return '';
    const labels = <String, String>{
      'producto': 'productos',
      'venta': 'ventas',
      'remito': 'remitos',
      'compra': 'compras',
      'cliente': 'clientes',
      'proveedor': 'proveedores',
      'stock_op': 'stock',
    };
    final parts = <String>[];
    var i = 0;
    for (final e in breakdown.entries) {
      if (i >= maxTypes) break;
      final name = labels[e.key] ?? e.key;
      parts.add('${e.value} $name');
      i++;
    }
    return parts.join(', ');
  }

  /// Lista corta de ops pendientes para el detalle del badge.
  Future<List<Map<String, dynamic>>> listPendingPreview({int limit = 20}) async {
    final db = await _db;
    return db.query(
      'sync_outbox',
      columns: [
        'op_id',
        'entity_type',
        'entity_local_id',
        'operation',
        'status',
        'attempts',
        'last_error',
        'updated_at',
        'priority',
        'lane',
      ],
      where: 'status IN (?, ?)',
      whereArgs: [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
      orderBy: 'priority ASC, id ASC',
      limit: limit,
    );
  }

  /// ACK upserts cuya fila local ya no existe (evita cola eterna).
  Future<int> ackOrphanUpserts() async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id', 'entity_type', 'entity_local_id'],
      where:
          "status IN (?, ?) AND operation = 'upsert' AND entity_local_id IS NOT NULL",
      whereArgs: [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
      limit: 200,
    );
    const tableByType = <String, String>{
      'producto': 'productos',
      'venta': 'ventas',
      'remito': 'remitos',
      'compra': 'compras',
      'cliente': 'clientes',
      'proveedor': 'proveedores',
    };
    var n = 0;
    for (final r in rows) {
      final type = r['entity_type']?.toString() ?? '';
      final localId = (r['entity_local_id'] as num?)?.toInt();
      final opId = r['op_id']?.toString() ?? '';
      final table = tableByType[type];
      if (table == null || localId == null || opId.isEmpty) continue;
      final exists = await db.query(
        table,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
      await ack(opId);
      n++;
    }
    return n;
  }

  /// Stock_ops trabados (reclaim eterno).
  ///
  /// **C6:** NUNCA ACK sin prueba de apply en nube. Sin [proveCloudApplied]
  /// se reencolan a `pending` (el apply remoto es idempotente por opId).
  /// Con prueba `true` → ACK; `false` → reencola.
  Future<int> purgeStuckStockOps({
    int minAttempts = 3,
    String? onlyLastErrorContains,
    Future<bool> Function(String remoteOpId)? proveCloudApplied,
    int limit = 300,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: [
        'op_id',
        'attempts',
        'last_error',
        'status',
        'entity_remote_id',
      ],
      where: "entity_type = 'stock_op' AND status IN (?, ?)",
      whereArgs: [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
      limit: limit,
    );
    var n = 0;
    final ahora = DateTime.now().toUtc().toIso8601String();
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final attempts = (r['attempts'] as num?)?.toInt() ?? 0;
      if (attempts < minAttempts) continue;
      final err = r['last_error']?.toString() ?? '';
      if (onlyLastErrorContains != null &&
          onlyLastErrorContains.isNotEmpty &&
          !err.contains(onlyLastErrorContains)) {
        continue;
      }
      final remoteOpId = r['entity_remote_id']?.toString() ??
          opId.replaceFirst('stock_op:', '');
      var proven = false;
      if (proveCloudApplied != null && remoteOpId.isNotEmpty) {
        try {
          proven = await proveCloudApplied(remoteOpId);
        } catch (_) {
          proven = false;
        }
      }
      if (proven) {
        await ack(opId);
      } else {
        // Reencolar: no tirar el movimiento.
        await db.update(
          'sync_outbox',
          {
            'status': SyncOutboxStatus.pending,
            'updated_at': ahora,
            'next_attempt_at': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 30))
                .toIso8601String(),
            'last_error': 'requeued_awaiting_cloud_proof',
          },
          where: 'op_id = ?',
          whereArgs: [opId],
        );
      }
      n++;
    }
    return n;
  }

  /// Reencola stock_op `dead` a pending con tope (no storm infinito).
  /// Conserva attempts (no reset a 0) para que vuelvan a dead si siguen fallando.
  Future<int> ackDeadStockOps({int limit = 50}) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id', 'attempts'],
      where: "entity_type = 'stock_op' AND status = ?",
      whereArgs: [SyncOutboxStatus.dead],
      limit: limit,
    );
    var n = 0;
    final ahora = DateTime.now().toUtc().toIso8601String();
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final attempts = (r['attempts'] as num?)?.toInt() ?? maxAttempts;
      // Si ya explotó el tope duro, no reabrir (poison pill).
      if (attempts >= maxAttempts) continue;
      n += await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'last_error': 'requeued_from_dead',
          'updated_at': ahora,
          'next_attempt_at': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 45))
              .toIso8601String(),
        },
        where: 'op_id = ?',
        whereArgs: [opId],
      );
    }
    return n;
  }

  /// Lista dead stock_ops (panel / cert / recover).
  Future<List<Map<String, dynamic>>> listDeadStockOps({int limit = 100}) async {
    final db = await _db;
    return db.query(
      'sync_outbox',
      columns: [
        'op_id',
        'entity_remote_id',
        'payload',
        'attempts',
        'last_error',
        'updated_at',
        'status',
      ],
      where: "entity_type = 'stock_op' AND status = ?",
      whereArgs: [SyncOutboxStatus.dead],
      orderBy: 'updated_at ASC',
      limit: limit,
    );
  }

  /// Reabre poison (`attempts >= maxAttempts`) de forma **explícita**.
  /// Resetea attempts a `maxAttempts - grace` para dar nuevas chances acotadas.
  Future<int> forceRequeuePoisonStockOps({
    int limit = 30,
    int graceAttempts = 3,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id', 'attempts'],
      where: "entity_type = 'stock_op' AND status = ?",
      whereArgs: [SyncOutboxStatus.dead],
      limit: limit,
    );
    var n = 0;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final resetTo = (maxAttempts - graceAttempts).clamp(0, maxAttempts - 1);
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final attempts = (r['attempts'] as num?)?.toInt() ?? 0;
      if (attempts < maxAttempts) continue; // no poison
      n += await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'attempts': resetTo,
          'last_error': 'force_requeue_poison',
          'updated_at': ahora,
          'next_attempt_at': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 20))
              .toIso8601String(),
        },
        where: 'op_id = ?',
        whereArgs: [opId],
      );
    }
    return n;
  }

  /// Recuperación completa de dead stock_ops:
  /// - cloud already applied → ACK
  /// - recoverable (attempts < max) → requeue
  /// - poison → force requeue (grace)
  Future<({int acked, int requeued, int forceRequeued})> recoverDeadStockOps({
    required Future<bool> Function(String remoteOpId) proveCloudApplied,
    int limit = 50,
  }) async {
    final rows = await listDeadStockOps(limit: limit);
    var acked = 0;
    var requeued = 0;
    var forceRequeued = 0;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final db = await _db;
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      final remoteOpId = r['entity_remote_id']?.toString() ??
          opId.replaceFirst('stock_op:', '');
      var proven = false;
      try {
        proven = await proveCloudApplied(remoteOpId);
      } catch (_) {
        proven = false;
      }
      if (proven) {
        await ack(opId);
        acked++;
        continue;
      }
      final attempts = (r['attempts'] as num?)?.toInt() ?? maxAttempts;
      if (attempts < maxAttempts) {
        requeued += await db.update(
          'sync_outbox',
          {
            'status': SyncOutboxStatus.pending,
            'last_error': 'recovered_from_dead',
            'updated_at': ahora,
            'next_attempt_at': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 30))
                .toIso8601String(),
          },
          where: 'op_id = ?',
          whereArgs: [opId],
        );
      } else {
        final resetTo = (maxAttempts - 3).clamp(0, maxAttempts - 1);
        forceRequeued += await db.update(
          'sync_outbox',
          {
            'status': SyncOutboxStatus.pending,
            'attempts': resetTo,
            'last_error': 'force_requeue_poison_recover',
            'updated_at': ahora,
            'next_attempt_at': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 20))
                .toIso8601String(),
          },
          where: 'op_id = ?',
          whereArgs: [opId],
        );
      }
    }
    return (acked: acked, requeued: requeued, forceRequeued: forceRequeued);
  }

  /// @Deprecated: preferir [purgeStuckStockOps] / [ackDeadStockOps].
  ///
  /// G3: **no-op**. ACK ciego de stock_ops perdía ops sin `status=applied`
  /// en nube (EXE→APK diverge). Conservado para no romper callers.
  Future<int> clearAllStockOpsOutbox() async {
    return 0;
  }

  /// @Deprecated — NUNCA ACK por set local. Solo cloud proof (auditoría 1.4.5).
  /// Conservado como no-op para no romper callers; siempre retorna 0.
  Future<int> ackStockOpsYaHechas(Set<String> hechas) async {
    // Intencionalmente vacío: ACK ciego por `_stockOpsHechas` perdía ops
    // que nunca llegaron a Firestore (EXE→APK stock diverge).
    return 0;
  }

  Future<bool> hasPendingLocalId(String entityType, int localId) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['id'],
      where:
          "entity_type = ? AND entity_local_id = ? AND status IN (?, ?) AND operation = ?",
      whereArgs: [
        entityType,
        localId,
        SyncOutboxStatus.pending,
        SyncOutboxStatus.inflight,
        'upsert',
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Capacidad 9: ¿hace falta encolar catch-up?
  /// true si nunca estuvo en outbox o quedó `dead` (no reabre `acked`).
  Future<bool> needsCatchupUpsert({
    required String entityType,
    required int localId,
  }) async {
    final db = await _db;
    final opId = 'upsert:$entityType:$localId';
    final rows = await db.query(
      'sync_outbox',
      columns: ['status'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final status = rows.first['status']?.toString() ?? '';
    return status == SyncOutboxStatus.dead;
  }

  /// Migra colas legacy de SharedPreferences (IDs) al outbox.
  /// No reabre `acked` (evita pendientes fantasma al reabrir la app).
  Future<void> migrateLegacyIdSet({
    required String entityType,
    required Iterable<int> ids,
  }) async {
    for (final id in ids) {
      await enqueueUpsert(
        entityType: entityType,
        localId: id,
        reopenAcked: false,
      );
    }
  }
}
