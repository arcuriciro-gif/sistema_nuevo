/// Traza E2E de una operación de sync (timestamps UTC ISO / epoch ms).
class SyncOpTrace {
  SyncOpTrace({
    required this.opId,
    required this.entityType,
    this.entityLocalId,
    this.entityRemoteId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String opId;
  final String entityType;
  final int? entityLocalId;
  final String? entityRemoteId;

  DateTime createdAt;
  DateTime? enqueuedAt;
  DateTime? claimedAt;
  DateTime? sendStartedAt;
  DateTime? firestoreDoneAt;
  DateTime? ackedAt;
  DateTime? remoteReceivedAt;
  DateTime? remoteAppliedAt;
  String? lastError;
  bool success = false;

  int? get totalMs {
    final end = ackedAt ?? firestoreDoneAt;
    if (end == null) return null;
    return end.difference(createdAt).inMilliseconds;
  }

  int? get waitMs {
    if (claimedAt == null) return null;
    final start = enqueuedAt ?? createdAt;
    return claimedAt!.difference(start).inMilliseconds;
  }

  int? get networkMs {
    if (sendStartedAt == null || firestoreDoneAt == null) return null;
    return firestoreDoneAt!.difference(sendStartedAt!).inMilliseconds;
  }

  int? get processMs {
    if (claimedAt == null || ackedAt == null) return null;
    final net = networkMs ?? 0;
    return ackedAt!.difference(claimedAt!).inMilliseconds - net;
  }

  int? get remoteHopMs {
    if (ackedAt == null || remoteAppliedAt == null) return null;
    return remoteAppliedAt!.difference(ackedAt!).inMilliseconds;
  }

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'entityType': entityType,
        'entityLocalId': entityLocalId,
        'entityRemoteId': entityRemoteId,
        'createdAt': createdAt.toIso8601String(),
        'enqueuedAt': enqueuedAt?.toIso8601String(),
        'claimedAt': claimedAt?.toIso8601String(),
        'sendStartedAt': sendStartedAt?.toIso8601String(),
        'firestoreDoneAt': firestoreDoneAt?.toIso8601String(),
        'ackedAt': ackedAt?.toIso8601String(),
        'remoteReceivedAt': remoteReceivedAt?.toIso8601String(),
        'remoteAppliedAt': remoteAppliedAt?.toIso8601String(),
        'totalMs': totalMs,
        'waitMs': waitMs,
        'networkMs': networkMs,
        'processMs': processMs,
        'remoteHopMs': remoteHopMs,
        'success': success,
        'lastError': lastError,
      };
}

/// Ring buffer + índice por opId (máx [capacity] trazas vivas).
class SyncTraceRegistry {
  SyncTraceRegistry._();
  static final SyncTraceRegistry instance = SyncTraceRegistry._();

  static const capacity = 2000;
  final Map<String, SyncOpTrace> _byOp = {};
  final List<String> _order = [];

  SyncOpTrace start({
    required String opId,
    required String entityType,
    int? entityLocalId,
    String? entityRemoteId,
  }) {
    final t = SyncOpTrace(
      opId: opId,
      entityType: entityType,
      entityLocalId: entityLocalId,
      entityRemoteId: entityRemoteId,
    );
    _put(t);
    return t;
  }

  SyncOpTrace? get(String opId) => _byOp[opId];

  SyncOpTrace ensure(
    String opId, {
    required String entityType,
    int? entityLocalId,
    String? entityRemoteId,
  }) {
    final existing = _byOp[opId];
    if (existing != null) return existing;
    return start(
      opId: opId,
      entityType: entityType,
      entityLocalId: entityLocalId,
      entityRemoteId: entityRemoteId,
    );
  }

  void markEnqueued(String opId) {
    final t = _byOp[opId];
    if (t == null) return;
    t.enqueuedAt ??= DateTime.now().toUtc();
  }

  void markClaimed(String opId) {
    final t = _byOp[opId];
    if (t == null) return;
    t.claimedAt = DateTime.now().toUtc();
  }

  void markSendStart(String opId) {
    final t = _byOp[opId];
    if (t == null) return;
    t.sendStartedAt = DateTime.now().toUtc();
  }

  void markFirestoreDone(String opId) {
    final t = _byOp[opId];
    if (t == null) return;
    t.firestoreDoneAt = DateTime.now().toUtc();
  }

  void markAcked(String opId, {bool success = true, String? error}) {
    final t = _byOp[opId];
    if (t == null) return;
    t.ackedAt = DateTime.now().toUtc();
    t.success = success;
    t.lastError = error;
  }

  void markRemoteApplied({
    required String entityType,
    int? entityLocalId,
    String? entityRemoteId,
  }) {
    for (final t in _byOp.values) {
      if (t.entityType != entityType) continue;
      if (entityLocalId != null && t.entityLocalId == entityLocalId) {
        t.remoteReceivedAt ??= DateTime.now().toUtc();
        t.remoteAppliedAt = DateTime.now().toUtc();
        return;
      }
      if (entityRemoteId != null &&
          t.entityRemoteId != null &&
          t.entityRemoteId == entityRemoteId) {
        t.remoteReceivedAt ??= DateTime.now().toUtc();
        t.remoteAppliedAt = DateTime.now().toUtc();
        return;
      }
    }
  }

  List<SyncOpTrace> recent({int limit = 100}) {
    final out = <SyncOpTrace>[];
    for (var i = _order.length - 1; i >= 0 && out.length < limit; i--) {
      final t = _byOp[_order[i]];
      if (t != null) out.add(t);
    }
    return out;
  }

  List<SyncOpTrace> completedForEntity(String entityType, {int limit = 200}) {
    final out = <SyncOpTrace>[];
    for (var i = _order.length - 1; i >= 0 && out.length < limit; i--) {
      final t = _byOp[_order[i]];
      if (t == null || t.entityType != entityType) continue;
      if (t.totalMs != null) out.add(t);
    }
    return out;
  }

  void _put(SyncOpTrace t) {
    if (_byOp.containsKey(t.opId)) {
      _byOp[t.opId] = t;
      return;
    }
    _byOp[t.opId] = t;
    _order.add(t.opId);
    while (_order.length > capacity) {
      final old = _order.removeAt(0);
      _byOp.remove(old);
    }
  }

  void resetForTests() {
    _byOp.clear();
    _order.clear();
  }
}
