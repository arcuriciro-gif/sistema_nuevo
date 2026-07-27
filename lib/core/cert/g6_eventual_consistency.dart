/// Definición formal G6 — convergencia eventual SQLite ↔ Firestore (stock).
///
/// ## Definición
///
/// Sea un sistema con:
/// - proyección local `S_i(p)` en SQLite dispositivo i
/// - proyección cloud `C(p)` en Firestore productos/{codigo}.stock
/// - historial cloud `stock_ops/{opId}` con status
/// - outbox local de stock_ops
///
/// **Quiescencia alcanzable** (predicado `Quiescent(i)`):
/// 1. `online = true`
/// 2. outbox stock_op en estados `pending∪inflight` = ∅
/// 3. dead stock_op = ∅ **o** toda dead tiene cloud `status=applied` (recuperada)
/// 4. hold-set `stock_ops_pull_holds` = ∅ **o** todos los holds con retry agotado
///    están a alarma (no bloquean watermark)
/// 5. no hay páginas de pull con ops `applied` aún no vistas en ledger local
///
/// **G6 (convergencia eventual):**
/// Si a partir de un estado finito se ejecuta un schedule finito de
/// `{Upload, Ack, PullWatermark, SoftPull, SweepHolds, RecoverDead, Reconcile}`
/// hasta `Quiescent(i)` para todo dispositivo i del tenant, entonces:
///
/// ```
/// ∀ producto p con codigo válido:
///   S_i(p) = C(p) = S_j(p)   ∀ dispositivos i,j
/// ```
///
/// y toda op originada localmente tiene `stock_ops.status = applied`.
///
/// ## Demostración (bosquejo)
///
/// Lema A (upload completo): cada LocalApply encola outbox en TX; Upload+Ack
/// solo tras cloud applied ⇒ al vaciar outbox, orígenes están a cloud.
///
/// Lema B (pull completo): watermark avanza solo si ops aplicadas o en holds;
/// sweeper vacía holds ⇒ toda op applied cloud llega al ledger peer.
///
/// Lema C (aditividad + G1): mismo conjunto de opIds aplicados ⇒ mismo stock.
///
/// De A+B+C: en quiescencia, todos ven el mismo conjunto de opIds applied ⇒ G6.
library;

/// Resultado de evaluar quiescencia / convergencia.
class G6Verdict {
  const G6Verdict({
    required this.quiescent,
    required this.converged,
    required this.reasons,
    required this.localStock,
    required this.cloudStock,
  });

  final bool quiescent;
  final bool converged;
  final List<String> reasons;
  final Map<String, int> localStock;
  final Map<String, int> cloudStock;

  bool get ok => quiescent && converged;
}

/// Evalúa G6 sobre snapshots (modelo / sim).
G6Verdict evaluateG6({
  required Map<String, int> localStock,
  required Map<String, int> cloudStock,
  required int outboxPending,
  required int outboxInflight,
  required int outboxDead,
  required int deadWithoutCloudApplied,
  required int pullHolds,
  required bool online,
  required Iterable<String> localOriginOpIds,
  required Map<String, String> cloudOpStatus,
}) {
  final reasons = <String>[];
  if (!online) reasons.add('offline');
  if (outboxPending > 0) reasons.add('outbox_pending=$outboxPending');
  if (outboxInflight > 0) reasons.add('outbox_inflight=$outboxInflight');
  if (deadWithoutCloudApplied > 0) {
    reasons.add('dead_unapplied=$deadWithoutCloudApplied');
  }
  if (pullHolds > 0) reasons.add('pull_holds=$pullHolds');

  for (final opId in localOriginOpIds) {
    final st = cloudOpStatus[opId];
    if (st != 'applied') {
      reasons.add('origin_op_not_applied:$opId=${st ?? 'missing'}');
    }
  }

  final mismatches = <String>[];
  final keys = {...localStock.keys, ...cloudStock.keys};
  for (final k in keys) {
    if ((localStock[k] ?? 0) != (cloudStock[k] ?? 0)) {
      mismatches.add('$k:local=${localStock[k]} cloud=${cloudStock[k]}');
    }
  }
  if (mismatches.isNotEmpty) {
    reasons.addAll(mismatches.map((m) => 'stock_mismatch:$m'));
  }

  final quiescent = online &&
      outboxPending == 0 &&
      outboxInflight == 0 &&
      deadWithoutCloudApplied == 0 &&
      pullHolds == 0 &&
      localOriginOpIds.every((id) => cloudOpStatus[id] == 'applied');

  final converged = quiescent && mismatches.isEmpty;

  return G6Verdict(
    quiescent: quiescent,
    converged: converged,
    reasons: reasons,
    localStock: Map.unmodifiable(localStock),
    cloudStock: Map.unmodifiable(cloudStock),
  );
}
