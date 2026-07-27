/// Modelo de referencia inmutable del motor de stock / sync.
///
/// Es el "ideal": reglas explícitas sin I/O. Cualquier secuencia de
/// [StockCertEvent] aplicada aquí define el estado correcto.
/// La implementación real debe converger al mismo stock por producto
/// (para el subconjunto de eventos que el harness ejecuta sobre SQLite).
library;

/// Estado cloud de una op.
enum RefCloudStatus { missing, pendingApply, claimed, applied }

/// Snapshot inmutable.
class StockRefState {
  const StockRefState({
    required this.stock,
    required this.ledgerBase,
    required this.ledgerSum,
    required this.appliedLocal,
    required this.appliedRemote,
    required this.outboxPending,
    required this.outboxDead,
    required this.cloudStatus,
    required this.cloudDelta,
    required this.cloudStock,
    required this.cloudIncrementApplied,
    required this.cloudClaim,
    this.online = true,
    this.lastError,
  });

  /// Proyección local por código de producto.
  final Map<String, int> stock;

  /// Primer stock_before (base de reconstrucción) por producto.
  final Map<String, int> ledgerBase;

  /// Σ delta del ledger por producto.
  final Map<String, int> ledgerSum;

  /// eventIds / opIds ya aplicados localmente.
  final Set<String> appliedLocal;
  final Set<String> appliedRemote;

  /// Outbox: ops esperando upload (opId cloud).
  final Set<String> outboxPending;
  final Set<String> outboxDead;

  /// Cloud stock_ops/{opId}.status
  final Map<String, RefCloudStatus> cloudStatus;
  final Map<String, int> cloudDelta;
  final Map<String, bool> cloudIncrementApplied;
  final Map<String, String> cloudClaim;

  /// Proyección cloud por código (solo increments).
  final Map<String, int> cloudStock;

  final bool online;
  final String? lastError;

  factory StockRefState.initial(Map<String, int> seedStock) {
    return StockRefState(
      stock: Map.unmodifiable(seedStock),
      ledgerBase: const {},
      ledgerSum: const {},
      appliedLocal: const {},
      appliedRemote: const {},
      outboxPending: const {},
      outboxDead: const {},
      cloudStatus: const {},
      cloudDelta: const {},
      cloudStock: Map.unmodifiable(seedStock),
      cloudIncrementApplied: const {},
      cloudClaim: const {},
    );
  }

  int reconstructed(String codigo) {
    final base = ledgerBase[codigo];
    if (base == null) return stock[codigo] ?? 0;
    return base + (ledgerSum[codigo] ?? 0);
  }

  bool projectionConsistent(String codigo) {
    if (!ledgerBase.containsKey(codigo)) return true;
    return stock[codigo] == reconstructed(codigo);
  }

  bool get allProjectionsConsistent =>
      stock.keys.every(projectionConsistent);

  /// G6 local↔cloud para ops acked: cloud applied y mismo stock por código
  /// tras sync exitosa (outbox vacía de pending).
  bool convergedAfterSuccessfulSync() {
    if (outboxPending.isNotEmpty) return false;
    for (final e in cloudStatus.entries) {
      if (e.value != RefCloudStatus.applied &&
          e.value != RefCloudStatus.missing) {
        // pending/claimed sin outbox = divergencia (op huérfana cloud)
        if (outboxDead.contains(e.key)) continue;
        return false;
      }
    }
    for (final cod in stock.keys) {
      if ((stock[cod] ?? 0) != (cloudStock[cod] ?? 0)) return false;
    }
    return true;
  }

  StockRefState copyWith({
    Map<String, int>? stock,
    Map<String, int>? ledgerBase,
    Map<String, int>? ledgerSum,
    Set<String>? appliedLocal,
    Set<String>? appliedRemote,
    Set<String>? outboxPending,
    Set<String>? outboxDead,
    Map<String, RefCloudStatus>? cloudStatus,
    Map<String, int>? cloudDelta,
    Map<String, int>? cloudStock,
    Map<String, bool>? cloudIncrementApplied,
    Map<String, String>? cloudClaim,
    bool? online,
    String? lastError,
    bool clearError = false,
  }) {
    return StockRefState(
      stock: Map.unmodifiable(stock ?? this.stock),
      ledgerBase: Map.unmodifiable(ledgerBase ?? this.ledgerBase),
      ledgerSum: Map.unmodifiable(ledgerSum ?? this.ledgerSum),
      appliedLocal: Set.unmodifiable(appliedLocal ?? this.appliedLocal),
      appliedRemote: Set.unmodifiable(appliedRemote ?? this.appliedRemote),
      outboxPending: Set.unmodifiable(outboxPending ?? this.outboxPending),
      outboxDead: Set.unmodifiable(outboxDead ?? this.outboxDead),
      cloudStatus: Map.unmodifiable(cloudStatus ?? this.cloudStatus),
      cloudDelta: Map.unmodifiable(cloudDelta ?? this.cloudDelta),
      cloudStock: Map.unmodifiable(cloudStock ?? this.cloudStock),
      cloudIncrementApplied:
          Map.unmodifiable(cloudIncrementApplied ?? this.cloudIncrementApplied),
      cloudClaim: Map.unmodifiable(cloudClaim ?? this.cloudClaim),
      online: online ?? this.online,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Eventos del modelo de referencia (= lenguaje de secuencias adversas).
sealed class StockCertEvent {
  const StockCertEvent();
}

/// Aplicación local de un movimiento comercial (venta/compra/remito/ajuste).
class LocalApply extends StockCertEvent {
  const LocalApply({
    required this.eventId,
    required this.codigo,
    required this.delta,
    this.documentType = 'ajuste',
    this.requireCodigo = true,
  });

  final String eventId;
  final String codigo;
  final int delta;
  final String documentType;
  final bool requireCodigo;

  String get cloudOpId => '${eventId}_$codigo';
}

/// Replay del mismo eventId (retry local).
class LocalReplay extends StockCertEvent {
  const LocalReplay({
    required this.eventId,
    required this.codigo,
    required this.delta,
  });
  final String eventId;
  final String codigo;
  final int delta;
}

/// Peer aplica stock_op remoto (mismo opId).
class RemoteApply extends StockCertEvent {
  const RemoteApply({
    required this.opId,
    required this.codigo,
    required this.delta,
  });
  final String opId;
  final String codigo;
  final int delta;
}

/// Intento de upload outbox → cloud (puede fallar si offline).
class UploadAttempt extends StockCertEvent {
  const UploadAttempt({this.opId, this.writerId = 'w1'});
  final String? opId; // null = primera pending
  final String writerId;
}

/// ACK solo si cloud applied (modelo ideal G3).
class AckIfApplied extends StockCertEvent {
  const AckIfApplied({required this.opId});
  final String opId;
}

class GoOffline extends StockCertEvent {
  const GoOffline();
}

class GoOnline extends StockCertEvent {
  const GoOnline();
}

/// Crash antes de commit: el evento LocalApply previo NO se aplicó.
/// En el modelo se representa como no-op explícito (la secuencia no incluye
/// el LocalApply, o se usa DiscardPending).
class CrashBeforeCommit extends StockCertEvent {
  const CrashBeforeCommit();
}

/// Crash después de commit: estado ya durable; no-op en modelo.
class CrashAfterCommit extends StockCertEvent {
  const CrashAfterCommit();
}

/// Poison: mueve outbox pending → dead (maxAttempts).
class PoisonOutbox extends StockCertEvent {
  const PoisonOutbox({required this.opId});
  final String opId;
}

/// Motor de referencia.
class StockReferenceModel {
  StockRefState reduce(StockRefState s, StockCertEvent e) {
    return switch (e) {
      LocalApply(:final eventId, :final codigo, :final delta, :final requireCodigo) =>
        _localApply(s, eventId, codigo, delta, requireCodigo),
      LocalReplay(:final eventId, :final codigo, :final delta) =>
        _localApply(s, eventId, codigo, delta, true),
      RemoteApply(:final opId, :final codigo, :final delta) =>
        _remoteApply(s, opId, codigo, delta),
      UploadAttempt(:final opId, :final writerId) =>
        _upload(s, opId, writerId),
      AckIfApplied(:final opId) => _ack(s, opId),
      GoOffline() => s.copyWith(online: false, clearError: true),
      GoOnline() => s.copyWith(online: true, clearError: true),
      CrashBeforeCommit() => s.copyWith(clearError: true),
      CrashAfterCommit() => s.copyWith(clearError: true),
      PoisonOutbox(:final opId) => _poison(s, opId),
    };
  }

  StockRefState reduceAll(StockRefState s, Iterable<StockCertEvent> events) {
    var cur = s;
    for (final e in events) {
      cur = reduce(cur, e);
    }
    return cur;
  }

  StockRefState _localApply(
    StockRefState s,
    String eventId,
    String codigo,
    int delta,
    bool requireCodigo,
  ) {
    if (delta == 0) return s;
    if (requireCodigo && codigo.trim().isEmpty) {
      return s.copyWith(lastError: 'G2: codigo vacío — apply rechazado');
    }
    if (s.appliedLocal.contains(eventId)) {
      return s; // G1
    }
    final cod = codigo.trim().isEmpty ? '_noid_' : codigo.trim();
    if (!s.stock.containsKey(cod) && cod != '_noid_') {
      // producto desconocido — rechazo (como real)
      return s.copyWith(lastError: 'producto inexistente $cod');
    }
    final before = s.stock[cod] ?? 0;
    final stock = Map<String, int>.from(s.stock)..[cod] = before + delta;
    final base = Map<String, int>.from(s.ledgerBase);
    base.putIfAbsent(cod, () => before);
    final sum = Map<String, int>.from(s.ledgerSum);
    sum[cod] = (sum[cod] ?? 0) + delta;
    final applied = Set<String>.from(s.appliedLocal)..add(eventId);
    final outbox = Set<String>.from(s.outboxPending)..add('${eventId}_$cod');
    final cloudDelta = Map<String, int>.from(s.cloudDelta)
      ..['${eventId}_$cod'] = delta;
    return s.copyWith(
      stock: stock,
      ledgerBase: base,
      ledgerSum: sum,
      appliedLocal: applied,
      outboxPending: outbox,
      cloudDelta: cloudDelta,
      clearError: true,
    );
  }

  StockRefState _remoteApply(
    StockRefState s,
    String opId,
    String codigo,
    int delta,
  ) {
    if (delta == 0 || opId.isEmpty) return s;
    if (s.appliedRemote.contains(opId) || s.appliedLocal.contains(opId)) {
      return s; // G1
    }
    final cod = codigo.trim();
    if (cod.isEmpty || !s.stock.containsKey(cod)) {
      return s.copyWith(lastError: 'remote skip missing $cod');
    }
    final before = s.stock[cod]!;
    final stock = Map<String, int>.from(s.stock)..[cod] = before + delta;
    final base = Map<String, int>.from(s.ledgerBase);
    base.putIfAbsent(cod, () => before);
    final sum = Map<String, int>.from(s.ledgerSum);
    sum[cod] = (sum[cod] ?? 0) + delta;
    final remote = Set<String>.from(s.appliedRemote)..add(opId);
    return s.copyWith(
      stock: stock,
      ledgerBase: base,
      ledgerSum: sum,
      appliedRemote: remote,
      clearError: true,
    );
  }

  /// Upload con protocolo claim (un writer gana).
  StockRefState _upload(StockRefState s, String? preferredOpId, String writerId) {
    if (!s.online) {
      return s.copyWith(lastError: 'offline');
    }
    String? opId = preferredOpId;
    if (opId == null) {
      for (final id in s.outboxPending) {
        if (s.cloudStatus[id] != RefCloudStatus.applied) {
          opId = id;
          break;
        }
      }
    }
    if (opId == null) return s; // nada pendiente de upload (solo ACK)
    final delta = s.cloudDelta[opId];
    if (delta == null || delta == 0) {
      return s.copyWith(lastError: 'upload sin delta $opId');
    }

    String? cod;
    for (final c in s.stock.keys) {
      if (opId.endsWith('_$c')) {
        cod = c;
        break;
      }
    }
    cod ??= opId.contains('_')
        ? opId.substring(opId.indexOf('_') + 1)
        : opId;

    final status = s.cloudStatus[opId] ?? RefCloudStatus.missing;
    if (status == RefCloudStatus.applied) {
      return s;
    }
    if (s.cloudIncrementApplied[opId] == true) {
      final st = Map<String, RefCloudStatus>.from(s.cloudStatus)
        ..[opId] = RefCloudStatus.applied;
      return s.copyWith(cloudStatus: st, clearError: true);
    }

    final claims = Map<String, String>.from(s.cloudClaim)..[opId] = writerId;
    final stMap = Map<String, RefCloudStatus>.from(s.cloudStatus)
      ..[opId] = RefCloudStatus.claimed;

    if (claims[opId] != writerId) {
      return s.copyWith(
        cloudClaim: claims,
        cloudStatus: stMap,
        lastError: 'lost claim',
      );
    }

    final cloudStock = Map<String, int>.from(s.cloudStock);
    cloudStock[cod] = (cloudStock[cod] ?? 0) + delta;
    final inc = Map<String, bool>.from(s.cloudIncrementApplied)..[opId] = true;
    stMap[opId] = RefCloudStatus.applied;

    return s.copyWith(
      cloudStock: cloudStock,
      cloudStatus: stMap,
      cloudIncrementApplied: inc,
      cloudClaim: claims,
      clearError: true,
    );
  }

  StockRefState _ack(StockRefState s, String opId) {
    // G3: solo si applied
    if (s.cloudStatus[opId] != RefCloudStatus.applied) {
      return s.copyWith(lastError: 'ACK rechazado: no applied');
    }
    final pending = Set<String>.from(s.outboxPending)..remove(opId);
    return s.copyWith(outboxPending: pending, clearError: true);
  }

  StockRefState _poison(StockRefState s, String opId) {
    final pending = Set<String>.from(s.outboxPending)..remove(opId);
    final dead = Set<String>.from(s.outboxDead)..add(opId);
    return s.copyWith(outboxPending: pending, outboxDead: dead, clearError: true);
  }
}
