import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Watermarks persistentes + registro de conflictos (Capacidad 2).
class SyncWatermarkStore {
  SyncWatermarkStore._();
  static final SyncWatermarkStore instance = SyncWatermarkStore._();

  Future<Set<String>> loadConfirmed(String collection) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_watermarks',
      where: 'collection = ?',
      whereArgs: [collection],
      limit: 1,
    );
    if (rows.isEmpty) return {};
    final raw = rows.first['confirmed_ids']?.toString() ?? '[]';
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveConfirmed(String collection, Set<String> ids) async {
    final db = await DatabaseHelper.instance.database;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode(ids.toList()..sort());
    await db.insert(
      'sync_watermarks',
      {
        'collection': collection,
        'confirmed_ids': payload,
        'updated_at': ahora,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> recordConflict({
    required String entityType,
    required String entityId,
    String? localRevision,
    String? remoteRevision,
    required String resolution,
    String? detail,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('sync_conflicts', {
      'entity_type': entityType,
      'entity_id': entityId,
      'local_revision': localRevision,
      'remote_revision': remoteRevision,
      'resolution': resolution,
      'detail': detail,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> conflictsSince(DateTime since) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM sync_conflicts WHERE created_at >= ?',
      [since.toUtc().toIso8601String()],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }
}
