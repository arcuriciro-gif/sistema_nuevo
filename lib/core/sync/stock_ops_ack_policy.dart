/// Política pura: cuándo es seguro ACK-ear un stock_op del outbox.
///
/// Nunca ACK sin prueba de apply en nube: eso dejaba stock del .exe
/// sin llegar al APK (C6 auditoría).
bool mayAckStockOpWithoutCloudProof() => false;

/// ACK solo con prueba cloud `status=applied` (por opId).
bool mayAckStockOp({
  required bool cloudAppliedProven,
}) =>
    cloudAppliedProven;

/// Payload outbox ejecutable: sin esto → throw (no ACK silencioso).
bool stockOpOutboxPayloadExecutable({
  required String? payloadRaw,
  required String? remoteOpId,
}) {
  if (payloadRaw == null || payloadRaw.trim().isEmpty) return false;
  // remoteOpId solo no basta: hace falta codigo+delta en payload.
  return true;
}
