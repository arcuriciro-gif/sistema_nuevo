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
  Future<void> enqueueUpsert({
    required String entityType,
    required int localId,
    String? remoteId,
    Map<String, dynamic>? payload,
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
  }) async {
    if (opId.isEmpty || codigo.isEmpty || delta == 0) return;
    await _upsertPending(
      SyncOutboxOp(
        opId: 'stock_op:$opId',
        entityType: 'stock_op',
        operation: 'upsert',
        entityRemoteId: opId,
        payloadJson: jsonEncode({
          'opId': opId,
          'codigo': codigo,
          'delta': delta,
        }),
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

  Future<void> _upsertPending(SyncOutboxOp op) async {
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
      // Reabrir si vuelve a encolarse (re-edit).
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
  Future<int> reclaimStaleInflight({
    Duration olderThan = const Duration(minutes: 5),
  }) async {
    final db = await _db;
    final cutoff =
        DateTime.now().toUtc().subtract(olderThan).toIso8601String();
    return db.update(
      'sync_outbox',
      {
        'status': SyncOutboxStatus.pending,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': 'reclaimed_stale_inflight',
      },
      where: "status = ? AND updated_at < ?",
      whereArgs: [SyncOutboxStatus.inflight, cutoff],
    );
  }

  Future<List<Map<String, dynamic>>> claimBatch({int limit = 40}) async {
    final db = await _db;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'sync_outbox',
      where:
          "status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
      whereArgs: [SyncOutboxStatus.pending, ahora],
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
      where: 'op_id = ?',
      whereArgs: [opId],
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

  /// Migra colas legacy de SharedPreferences (IDs) al outbox.
  Future<void> migrateLegacyIdSet({
    required String entityType,
    required Iterable<int> ids,
  }) async {
    for (final id in ids) {
      await enqueueUpsert(entityType: entityType, localId: id);
    }
  }
}
