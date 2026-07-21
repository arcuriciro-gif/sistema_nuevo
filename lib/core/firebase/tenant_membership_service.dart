import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';

/// Asegura tenant + membership para que las Security Rules permitan sync.
class TenantMembershipService {
  TenantMembershipService._();

  static final TenantMembershipService instance = TenantMembershipService._();

  DocumentReference<Map<String, dynamic>> _tenantRef(String tenantId) {
    return FirebaseFirestore.instance.collection('tenants').doc(tenantId);
  }

  DocumentReference<Map<String, dynamic>> _memberRef(
    String tenantId,
    String uid,
  ) {
    return _tenantRef(tenantId).collection('members').doc(uid);
  }

  /// Crea/actualiza tenant (owner) y members/{uid} con el rol local.
  /// Idempotente. No lanza: registra y sigue (sync puede reintentar).
  Future<bool> asegurarMembresia({
    required String rol,
    String? email,
    String? usuario,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final uid = FirebaseAuthUsuarioService.instance.uidActual;
    if (uid == null || uid.isEmpty) return false;

    final tenantId = BackendConfigService.instance.tenantId;
    final ahora = DateTime.now().toUtc().toIso8601String();
    final rolNorm = rol.trim().isEmpty ? 'empleado' : rol.trim().toLowerCase();

    try {
      final tenantRef = _tenantRef(tenantId);
      final tenantSnap = await tenantRef.get();
      if (!tenantSnap.exists) {
        await tenantRef.set({
          'ownerUid': uid,
          'allowSelfJoin': true,
          'creadoEn': ahora,
          'actualizadoEn': ahora,
        });
        debugPrint('TenantMembership: tenant $tenantId creado owner=$uid');
      } else {
        final data = tenantSnap.data() ?? {};
        if (data['ownerUid'] == null || (data['ownerUid'] as String).isEmpty) {
          await tenantRef.set({
            'ownerUid': uid,
            'allowSelfJoin': data['allowSelfJoin'] ?? true,
            'actualizadoEn': ahora,
          }, SetOptions(merge: true));
        }
      }

      await _memberRef(tenantId, uid).set({
        'uid': uid,
        'rol': rolNorm,
        'activo': true,
        if (email != null && email.isNotEmpty) 'email': email,
        if (usuario != null && usuario.isNotEmpty) 'usuario': usuario,
        'actualizadoEn': ahora,
      }, SetOptions(merge: true));

      debugPrint('TenantMembership: member OK tenant=$tenantId uid=$uid rol=$rolNorm');
      return true;
    } catch (e, st) {
      debugPrint('TenantMembership error: $e\n$st');
      return false;
    }
  }
}
