import 'package:sqflite/sqflite.dart';

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

/// Suma deltas del ledger para un documento, cubriendo id estable y legado.
Future<int> ledgerNetForDocumentCandidates(
  DatabaseExecutor txn, {
  required String documentType,
  required String? numero,
  required int localId,
}) async {
  final keys = ledgerDocumentIdCandidates(numero: numero, localId: localId);
  final placeholders = List.filled(keys.length, '?').join(',');
  final r = await txn.rawQuery(
    'SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger '
    'WHERE document_type = ? AND document_id IN ($placeholders)',
    [documentType, ...keys],
  );
  return (r.first['s'] as num?)?.toInt() ?? 0;
}
