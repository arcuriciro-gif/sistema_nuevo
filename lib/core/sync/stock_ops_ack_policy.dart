/// Política pura: cuándo es seguro ACK-ear un stock_op del outbox.
///
/// Nunca ACK sin prueba de apply en nube: eso dejaba stock del .exe
/// sin llegar al APK (C6 auditoría).
bool mayAckStockOpWithoutCloudProof() => false;

/// ACK solo si el producto en nube ya refleja la op (`ultimaStockOp == opId`)
/// o el doc stock_ops está `applied` y el producto coincide.
bool mayAckStockOp({
  required bool cloudAppliedProven,
}) =>
    cloudAppliedProven;
