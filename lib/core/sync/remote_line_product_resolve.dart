/// Resolución de líneas remotas (remito/venta/compra) → producto local.
///
/// El `productoId` del peer es autoincrement SQLite: **nunca** es válido
/// cross-device. Solo `productoCodigo` → id local.
///
/// Regresión 1.4.10 (`PRAGMA foreign_keys=ON`): usar el id del peer cuando
/// el producto aún no existe en el APK → FK fail → abortaba TODO el apply
/// de remitos → APK sin remitos aunque existieran en Firestore.
int? resolveRemoteLineProductoId({
  required int? peerProductoId,
  required String? codigo,
  required Map<String, int> localIdByCodigo,
}) {
  final cod = (codigo ?? '').trim();
  if (cod.isEmpty) return null;
  return localIdByCodigo[cod];
}
