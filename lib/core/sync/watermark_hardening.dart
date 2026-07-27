/// Watermark hardening: nunca avanzar si quedan eventos sin procesar
/// y sin park en hold-set.
library;

export 'stock_ops_pull_policy.dart' show shouldAdvanceStockOpsWatermark;
