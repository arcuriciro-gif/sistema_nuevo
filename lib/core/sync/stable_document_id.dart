/// Identidad global estable para documentos comerciales (hardening).
///
/// Nunca usar autoincrement local como autoridad cross-device:
/// cada nodo asigna ids distintos → tombstone/ledger divergen.
///
/// Autoridad: `numero` de negocio (Firestore doc id). Fallback solo si falta.
String stableCommercialDocumentId({
  required String? numero,
  required int localId,
  String fallbackPrefix = '',
}) {
  final n = (numero ?? '').trim();
  if (n.isNotEmpty) return n;
  if (fallbackPrefix.isEmpty) return '$localId';
  return '$fallbackPrefix$localId';
}

/// Claves candidatas para buscar en ledger (nuevo + legado local-id).
List<String> ledgerDocumentIdCandidates({
  required String? numero,
  required int localId,
}) {
  final keys = <String>[];
  final n = (numero ?? '').trim();
  if (n.isNotEmpty) keys.add(n);
  keys.add('$localId');
  return keys;
}
