import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../database/database_helper.dart';

/// Estado durable del scheduler (sobrevive kill / corte de luz).
class SchedulerPersistentState {
  SchedulerPersistentState({
    required this.mode,
    required this.turboActive,
    required this.adaptiveBatchL1,
    required this.adaptiveBatchBg,
    required this.lastFirestoreLatencyMs,
    required this.updatedAt,
    this.checkpointJson,
  });

  final String mode;
  final bool turboActive;
  final int adaptiveBatchL1;
  final int adaptiveBatchBg;
  final double lastFirestoreLatencyMs;
  final String updatedAt;
  final String? checkpointJson;

  Map<String, dynamic> toMap() => {
        'id': 1,
        'mode': mode,
        'turbo_active': turboActive ? 1 : 0,
        'adaptive_batch_l1': adaptiveBatchL1,
        'adaptive_batch_bg': adaptiveBatchBg,
        'last_firestore_latency_ms': lastFirestoreLatencyMs,
        'checkpoint_json': checkpointJson,
        'updated_at': updatedAt,
      };

  static SchedulerPersistentState fromMap(Map<String, dynamic> m) =>
      SchedulerPersistentState(
        mode: m['mode']?.toString() ?? 'idle',
        turboActive: ((m['turbo_active'] as num?)?.toInt() ?? 0) == 1,
        adaptiveBatchL1: (m['adaptive_batch_l1'] as num?)?.toInt() ?? 10,
        adaptiveBatchBg: (m['adaptive_batch_bg'] as num?)?.toInt() ?? 20,
        lastFirestoreLatencyMs:
            (m['last_firestore_latency_ms'] as num?)?.toDouble() ?? 0,
        updatedAt: m['updated_at']?.toString() ?? '',
        checkpointJson: m['checkpoint_json']?.toString(),
      );
}

class SchedulerStateStore {
  SchedulerStateStore._();
  static final SchedulerStateStore instance = SchedulerStateStore._();

  Future<Database> get _db async => DatabaseHelper.instance.database;

  Future<SchedulerPersistentState?> load() async {
    final db = await _db;
    final rows = await db.query(
      'sync_scheduler_state',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SchedulerPersistentState.fromMap(rows.first);
  }

  Future<void> save({
    required String mode,
    required bool turboActive,
    required int adaptiveBatchL1,
    required int adaptiveBatchBg,
    required double lastFirestoreLatencyMs,
    Map<String, dynamic>? checkpoint,
  }) async {
    final db = await _db;
    final state = SchedulerPersistentState(
      mode: mode,
      turboActive: turboActive,
      adaptiveBatchL1: adaptiveBatchL1,
      adaptiveBatchBg: adaptiveBatchBg,
      lastFirestoreLatencyMs: lastFirestoreLatencyMs,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      checkpointJson: checkpoint == null ? null : jsonEncode(checkpoint),
    );
    await db.insert(
      'sync_scheduler_state',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
