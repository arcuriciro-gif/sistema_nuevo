/// Helpers de tombstone remoto (Capacidad 7).
///
/// Un doc remoto se considera eliminado si trae `tombstone: true` o `deletedAt`.
bool isRemoteTombstone(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data['tombstone'] == true) return true;
  final deletedAt = data['deletedAt']?.toString();
  return deletedAt != null && deletedAt.isNotEmpty;
}

/// Payload mínimo para marcar un documento como eliminado en la nube.
Map<String, dynamic> buildTombstonePayload({
  required String opId,
  required String deletedBy,
  DateTime? at,
}) {
  return {
    'deletedAt': (at ?? DateTime.now().toUtc()).toIso8601String(),
    'deletedBy': deletedBy,
    'tombstone': true,
    'opId': opId,
  };
}
