import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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
  });

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
    };
  }
}

/// Cola durable con ACK explícito. No se borra hasta confirmar remoto.
class SyncOutbox {
  SyncOutbox._();
  static final SyncOutbox instance = SyncOutbox._();

  static const maxAttempts = 12;

  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// Encola upsert. Idempotente por opId estable.
  ///
  /// [reopenAcked]: `true` (default) ante edición real del usuario.
  /// `false` al absorber colas legacy / catch-up — no reabre lo ya sincronizado
  /// (evita "N pendientes" fantasma al login en Windows).
  Future<void> enqueueUpsert({
    required String entityType,
    required int localId,
    String? remoteId,
    Map<String, dynamic>? payload,
    bool reopenAcked = true,
  }) async {
    final opId = 'upsert:$entityType:$localId';
    await _upsertPending(
      SyncOutboxOp(
        opId: opId,
        entityType: entityType,
        operation: 'upsert',
        entityLocalId: localId,
        entityRemoteId: remoteId,
        payloadJson: payload == null ? null : jsonEncode(payload),
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
    final payload = <String, dynamic>{
      'opId': opId,
      'codigo': codigo,
      'delta': delta,
    };
    final dt = (documentType ?? '').trim();
    final di = (documentId ?? '').trim();
    if (dt.isNotEmpty) payload['documentType'] = dt;
    if (di.isNotEmpty) payload['documentId'] = di;
    await _upsertPending(
      SyncOutboxOp(
        opId: 'stock_op:$opId',
        entityType: 'stock_op',
        operation: 'upsert',
        entityRemoteId: opId,
        payloadJson: jsonEncode(payload),
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
    final existing = await db.query(
      'sync_outbox',
      where: 'op_id = ?',
      whereArgs: [op.opId],
      limit: 1,
    );
    final ahora = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('sync_outbox', op.toInsertMap());
      return;
    }
    final status = existing.first['status']?.toString() ?? '';
    if (status == SyncOutboxStatus.acked) {
      if (!reopenAcked) return;
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'attempts': 0,
          'last_error': null,
          'updated_at': ahora,
          'next_attempt_at': null,
          'payload': op.payloadJson,
          'entity_remote_id': op.entityRemoteId,
        },
        where: 'op_id = ?',
        whereArgs: [op.opId],
      );
      return;
    }
    if (status == SyncOutboxStatus.dead) {
      // Dead siempre se puede reintentar (catch-up / migración).
      await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'attempts': 0,
          'last_error': null,
          'updated_at': ahora,
          'next_attempt_at': null,
          'payload': op.payloadJson,
          'entity_remote_id': op.entityRemoteId,
        },
        where: 'op_id = ?',
        whereArgs: [op.opId],
      );
      return;
    }
    if (status == SyncOutboxStatus.inflight ||
        status == SyncOutboxStatus.pending) {
      await db.update(
        'sync_outbox',
        {
          'updated_at': ahora,
          'payload': op.payloadJson ?? existing.first['payload'],
          'entity_remote_id':
              op.entityRemoteId ?? existing.first['entity_remote_id'],
        },
        where: 'op_id = ?',
        whereArgs: [op.opId],
      );
    }
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

  Future<List<Map<String, dynamic>>> claimBatch({
    int limit = 40,
    List<String>? entityTypes,
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
    final rows = await db.query(
      'sync_outbox',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'id ASC',
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
      ],
      where: 'status IN (?, ?)',
      whereArgs: [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
      orderBy: 'id ASC',
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
      limit: 300,
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

  /// Reencola stock_op `dead` a pending (C6: no ACK ciego).
  /// El apply es idempotente; con pending_apply→applied se completa.
  Future<int> ackDeadStockOps() async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id'],
      where: "entity_type = 'stock_op' AND status = ?",
      whereArgs: [SyncOutboxStatus.dead],
      limit: 500,
    );
    var n = 0;
    final ahora = DateTime.now().toUtc().toIso8601String();
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      n += await db.update(
        'sync_outbox',
        {
          'status': SyncOutboxStatus.pending,
          'attempts': 0,
          'last_error': 'requeued_from_dead',
          'updated_at': ahora,
          'next_attempt_at': null,
        },
        where: 'op_id = ?',
        whereArgs: [opId],
      );
    }
    return n;
  }

  /// @Deprecated: preferir [purgeStuckStockOps] / [ackDeadStockOps].
  /// No usar en pump: borraba stock fresco y el APK no veía cambios.
  Future<int> clearAllStockOpsOutbox() async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id'],
      where: "entity_type = 'stock_op' AND status IN (?, ?, ?)",
      whereArgs: [
        SyncOutboxStatus.pending,
        SyncOutboxStatus.inflight,
        SyncOutboxStatus.dead,
      ],
      limit: 500,
    );
    var n = 0;
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      await ack(opId);
      n++;
    }
    return n;
  }

  /// ACK stock_ops ya aplicadas localmente (opId en [hechas]).
  Future<int> ackStockOpsYaHechas(Set<String> hechas) async {
    if (hechas.isEmpty) return 0;
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['op_id', 'entity_remote_id', 'payload'],
      where: "status IN (?, ?) AND entity_type = 'stock_op'",
      whereArgs: [SyncOutboxStatus.pending, SyncOutboxStatus.inflight],
      limit: 200,
    );
    var n = 0;
    for (final r in rows) {
      final opId = r['op_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      var stockOpId = r['entity_remote_id']?.toString() ?? '';
      if (stockOpId.isEmpty) {
        final payload = r['payload']?.toString();
        if (payload != null && payload.isNotEmpty) {
          try {
            final m = jsonDecode(payload);
            if (m is Map) stockOpId = m['opId']?.toString() ?? '';
          } catch (_) {}
        }
      }
      // op_id outbox = "stock_op:$opId"
      final bare = opId.startsWith('stock_op:')
          ? opId.substring('stock_op:'.length)
          : opId;
      if (hechas.contains(stockOpId) || hechas.contains(bare)) {
        await ack(opId);
        n++;
      }
    }
    return n;
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
