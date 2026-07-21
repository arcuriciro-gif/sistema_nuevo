import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import 'sync_outbox.dart';

/// Catch-up paginado de documentos locales → outbox (Capacidad 9 / roadmap B6).
///
/// Evita el techo oculto de “últimos 2000” y no reabre ops ya `acked`
/// (solo encola ausentes o `dead`).
class SyncCatchup {
  SyncCatchup._();
  static final SyncCatchup instance = SyncCatchup._();

  static const defaultPageSize = 250;
  static const defaultMaxPagesPerCycle = 8; // hasta 2000/ciclo, rotando

  /// Avanza el cursor de [table]/[entityType] y encola upserts necesarios.
  ///
  /// Retorna cuántos IDs encoló en este ciclo.
  Future<int> enqueueDocumentCatchup({
    required Database db,
    required String table,
    required String entityType,
    int pageSize = defaultPageSize,
    int maxPagesPerCycle = defaultMaxPagesPerCycle,
  }) async {
    var afterId = await loadCursor(entityType);
    var enqueued = 0;
    var completedPass = false;

    for (var page = 0; page < maxPagesPerCycle; page++) {
      final rows = await db.query(
        table,
        columns: ['id'],
        where: 'id > ?',
        whereArgs: [afterId],
        orderBy: 'id ASC',
        limit: pageSize,
      );
      if (rows.isEmpty) {
        await saveCursor(entityType, 0);
        completedPass = true;
        break;
      }

      for (final row in rows) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        afterId = id;
        if (!await SyncOutbox.instance.needsCatchupUpsert(
          entityType: entityType,
          localId: id,
        )) {
          continue;
        }
        await SyncOutbox.instance.enqueueUpsert(
          entityType: entityType,
          localId: id,
        );
        enqueued++;
      }
      await saveCursor(entityType, afterId);
    }

    if (completedPass) {
      // Señal para health / panel técnico.
      return enqueued;
    }
    return enqueued;
  }

  Future<int> loadCursor(String entityType) async {
    final db = await DatabaseHelper.instance.database;
    final key = _cursorKey(entityType);
    final rows = await db.query(
      'sync_watermarks',
      where: 'collection = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final raw = rows.first['confirmed_ids']?.toString() ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return (decoded['afterId'] as num?)?.toInt() ?? 0;
      }
      if (decoded is num) return decoded.toInt();
    } catch (_) {}
    return 0;
  }

  Future<void> saveCursor(String entityType, int afterId) async {
    final db = await DatabaseHelper.instance.database;
    final key = _cursorKey(entityType);
    final ahora = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'sync_watermarks',
      {
        'collection': key,
        'confirmed_ids': jsonEncode({'afterId': afterId}),
        'updated_at': ahora,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _cursorKey(String entityType) => 'catchup_cursor:$entityType';
}
