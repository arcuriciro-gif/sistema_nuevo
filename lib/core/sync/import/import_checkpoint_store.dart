import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../database/database_helper.dart';

/// Checkpoint durable de importaciones masivas (reanudable tras kill).
class ImportCheckpoint {
  ImportCheckpoint({
    required this.jobId,
    required this.sourceName,
    required this.totalRows,
    required this.nextRowIndex,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.status,
    required this.updatedAt,
    this.mappingJson,
  });

  final String jobId;
  final String sourceName;
  final int totalRows;
  final int nextRowIndex;
  final int imported;
  final int updated;
  final int skipped;
  final String status; // running | paused | done | cancelled
  final String updatedAt;
  final String? mappingJson;

  bool get isDone => status == 'done' || status == 'cancelled';
  double get progress =>
      totalRows <= 0 ? 0 : (nextRowIndex / totalRows).clamp(0.0, 1.0);

  Map<String, dynamic> toMap() => {
        'job_id': jobId,
        'source_name': sourceName,
        'total_rows': totalRows,
        'next_row_index': nextRowIndex,
        'imported': imported,
        'updated': updated,
        'skipped': skipped,
        'status': status,
        'updated_at': updatedAt,
        'mapping_json': mappingJson,
      };

  static ImportCheckpoint fromMap(Map<String, dynamic> m) => ImportCheckpoint(
        jobId: m['job_id']?.toString() ?? '',
        sourceName: m['source_name']?.toString() ?? '',
        totalRows: (m['total_rows'] as num?)?.toInt() ?? 0,
        nextRowIndex: (m['next_row_index'] as num?)?.toInt() ?? 0,
        imported: (m['imported'] as num?)?.toInt() ?? 0,
        updated: (m['updated'] as num?)?.toInt() ?? 0,
        skipped: (m['skipped'] as num?)?.toInt() ?? 0,
        status: m['status']?.toString() ?? 'running',
        updatedAt: m['updated_at']?.toString() ?? '',
        mappingJson: m['mapping_json']?.toString(),
      );
}

class ImportCheckpointStore {
  ImportCheckpointStore._();
  static final ImportCheckpointStore instance = ImportCheckpointStore._();

  Future<Database> get _db async => DatabaseHelper.instance.database;

  Future<ImportCheckpoint> startJob({
    required String sourceName,
    required int totalRows,
    Map<String, int?>? mapping,
  }) async {
    final job = ImportCheckpoint(
      jobId: const Uuid().v4(),
      sourceName: sourceName,
      totalRows: totalRows,
      nextRowIndex: 0,
      imported: 0,
      updated: 0,
      skipped: 0,
      status: 'running',
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      mappingJson: mapping == null ? null : jsonEncode(mapping),
    );
    final db = await _db;
    await db.insert('import_jobs', job.toMap());
    return job;
  }

  Future<ImportCheckpoint?> loadRunning() async {
    final db = await _db;
    final rows = await db.query(
      'import_jobs',
      where: 'status = ?',
      whereArgs: ['running'],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ImportCheckpoint.fromMap(rows.first);
  }

  Future<void> saveProgress(ImportCheckpoint job) async {
    final db = await _db;
    final updated = ImportCheckpoint(
      jobId: job.jobId,
      sourceName: job.sourceName,
      totalRows: job.totalRows,
      nextRowIndex: job.nextRowIndex,
      imported: job.imported,
      updated: job.updated,
      skipped: job.skipped,
      status: job.status,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      mappingJson: job.mappingJson,
    );
    await db.update(
      'import_jobs',
      updated.toMap(),
      where: 'job_id = ?',
      whereArgs: [job.jobId],
    );
  }

  Future<void> markDone(String jobId) async {
    final db = await _db;
    await db.update(
      'import_jobs',
      {
        'status': 'done',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }

  Future<void> markCancelled(String jobId) async {
    final db = await _db;
    await db.update(
      'import_jobs',
      {
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }
}
