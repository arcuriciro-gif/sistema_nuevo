import 'package:flutter/foundation.dart';

import 'sync_flight_recorder.dart';

/// Logs estructurados del Sync Engine para trazabilidad E2E.
///
/// Cada evento incluye: eventId, entityId, opId, transactionId, deviceId.
/// Formato: una línea JSON prefijada `SYNC_PATH` (filtrable en logcat/console).
class SyncPathLogger {
  SyncPathLogger._();
  static final SyncPathLogger instance = SyncPathLogger._();

  String deviceId = 'unknown';
  final List<Map<String, dynamic>> _ring = [];
  static const _capacity = 500;

  void configure({required String deviceId}) {
    this.deviceId = deviceId.trim().isEmpty ? 'unknown' : deviceId.trim();
  }

  /// Emite un hop del recorrido Windows → Firestore → Android → UI.
  void hop({
    required String stage,
    required String entityType,
    String? eventId,
    String? entityId,
    String? opId,
    String? transactionId,
    String? outcome,
    Map<String, Object?> extra = const {},
  }) {
    final payload = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'stage': stage,
      'entityType': entityType,
      'eventId': eventId,
      'entityId': entityId,
      'opId': opId,
      'transactionId': transactionId,
      'deviceId': deviceId,
      'outcome': outcome,
      ...extra,
    };
    _ring.add(payload);
    while (_ring.length > _capacity) {
      _ring.removeAt(0);
    }
    // ignore: avoid_print — forense: debe ser visible en release/profile también
    debugPrint('SYNC_PATH ${payload.toString()}');
    SyncFlightRecorder.instance.record(
      kind: 'path_$stage',
      message: outcome ?? stage,
      opId: opId,
      entityType: entityType,
      data: payload,
    );
  }

  List<Map<String, dynamic>> dump({int n = 100}) {
    if (_ring.length <= n) return List.unmodifiable(_ring);
    return List.unmodifiable(_ring.sublist(_ring.length - n));
  }

  List<Map<String, dynamic>> forEntity(String entityId) =>
      _ring.where((e) => e['entityId'] == entityId).toList(growable: false);

  void resetForTests() {
    _ring.clear();
    deviceId = 'test-device';
  }
}
