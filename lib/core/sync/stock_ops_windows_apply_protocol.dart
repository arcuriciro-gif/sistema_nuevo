/// Protocolo puro Windows (sin Firestore txn) para aplicar una stock_op.
///
/// Invariantes que el caller debe respetar:
/// 1. Nunca incrementar si [WindowsStockOpStep.done] o [sealAppliedOnly].
/// 2. Antes de incrementar: escribir claim y re-leer; solo el dueño avanza.
/// 3. Increment + `status=applied` + `incrementApplied=true` en el mismo
///    WriteBatch (atómico). Así no hay ventana "incrementó pero no applied".
/// 4. Si se pierde el claim → [retryLater] (outbox queda pending; no ACK).
library;

enum WindowsStockOpStep {
  /// Ya terminal: no-op.
  done,

  /// `incrementApplied` ya es true pero status≠applied → solo sellar applied.
  sealAppliedOnly,

  /// Crear doc pending_apply con nuestro claim.
  createPendingWithClaim,

  /// Reclamar op existente (pending/claimed) con nuestro claim.
  claimExisting,

  /// Somos dueños del claim y aún no se incrementó → batch increment+applied.
  incrementAndSeal,

  /// Otro writer tiene el claim o estado ambiguo → reintentar (no ACK).
  retryLater,
}

class WindowsStockOpSnapshot {
  const WindowsStockOpSnapshot({
    required this.exists,
    required this.status,
    required this.incrementApplied,
    required this.claim,
  });

  final bool exists;
  final String? status;
  final bool incrementApplied;
  final String? claim;

  bool get isApplied => (status ?? '').trim() == 'applied';
}

/// Decisión tras leer el doc (antes de mutar).
WindowsStockOpStep decideWindowsStockOpAfterRead(WindowsStockOpSnapshot snap) {
  if (!snap.exists) return WindowsStockOpStep.createPendingWithClaim;
  if (snap.isApplied) return WindowsStockOpStep.done;
  if (snap.incrementApplied) return WindowsStockOpStep.sealAppliedOnly;
  return WindowsStockOpStep.claimExisting;
}

/// Decisión tras escribir claim y re-leer.
WindowsStockOpStep decideWindowsStockOpAfterClaim({
  required WindowsStockOpSnapshot snap,
  required String ourClaim,
}) {
  if (snap.isApplied) return WindowsStockOpStep.done;
  if (snap.incrementApplied) return WindowsStockOpStep.sealAppliedOnly;
  final theirs = (snap.claim ?? '').trim();
  if (theirs.isEmpty || theirs != ourClaim) {
    return WindowsStockOpStep.retryLater;
  }
  return WindowsStockOpStep.incrementAndSeal;
}

/// ¿Esta decisión permite FieldValue.increment?
bool windowsStepMayIncrement(WindowsStockOpStep step) =>
    step == WindowsStockOpStep.incrementAndSeal;
