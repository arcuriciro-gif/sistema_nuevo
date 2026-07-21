import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth/rol_util.dart';
import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import 'device_trust_service.dart';

/// Asegura tenant + membership para que las Security Rules permitan sync.
///
/// Capacidad 1:
/// - Nuevos tenants: `allowSelfJoin: false`.
/// - No auto-eleva rol si el member ya existe.
/// - Self-join legado nunca pide rol admin.
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
    if (tenantId.isEmpty) {
      debugPrint('TenantMembership: tenantId vacío — abort');
      return false;
    }

    final ahora = DateTime.now().toUtc().toIso8601String();
    final rolNorm = RolUtil.normalizar(
      rol.trim().isEmpty ? 'empleado' : rol.trim(),
    );

    try {
      final tenantRef = _tenantRef(tenantId);
      final tenantSnap = await tenantRef.get();
      var soyOwner = false;

      if (!tenantSnap.exists) {
        await tenantRef.set({
          'ownerUid': uid,
          'allowSelfJoin': false,
          'creadoEn': ahora,
          'actualizadoEn': ahora,
        });
        soyOwner = true;
        debugPrint('TenantMembership: tenant $tenantId creado owner=$uid');
      } else {
        final data = tenantSnap.data() ?? {};
        final owner = data['ownerUid']?.toString() ?? '';
        soyOwner = owner == uid;
        if (owner.isEmpty) {
          await tenantRef.set({
            'ownerUid': uid,
            'allowSelfJoin': false,
            'actualizadoEn': ahora,
          }, SetOptions(merge: true));
          soyOwner = true;
        }
      }

      final memberRef = _memberRef(tenantId, uid);
      final memberSnap = await memberRef.get();

      if (memberSnap.exists) {
        // Nunca pisar rol/activo remotos (anti auto-elevate).
        final patch = <String, dynamic>{
          'actualizadoEn': ahora,
          if (email != null && email.isNotEmpty) 'email': email,
          if (usuario != null && usuario.isNotEmpty) 'usuario': usuario,
        };
        await memberRef.set(patch, SetOptions(merge: true));
      } else {
        // Primer member: owner → admin. Si no es owner, rol local
        // (self-join legado no puede ser admin por rules).
        final rolAlta = soyOwner ? RolUtil.administrador : rolNorm;
        final rolSeguro = (!soyOwner && rolAlta == RolUtil.administrador)
            ? RolUtil.empleado
            : rolAlta;

        await memberRef.set({
          'uid': uid,
          'rol': rolSeguro,
          'activo': true,
          if (email != null && email.isNotEmpty) 'email': email,
          if (usuario != null && usuario.isNotEmpty) 'usuario': usuario,
          'actualizadoEn': ahora,
        });
      }

      // Claims: si el token ya trae tenantId/rol, solo log; la autoridad
      // actual de rules es members/{uid}. Custom claims vía Admin SDK = Fase posterior.
      await _logClaimsSiExisten();

      await DeviceTrustService.instance.registrarDispositivoActual();

      debugPrint(
        'TenantMembership: member OK tenant=$tenantId uid=$uid',
      );
      return true;
    } catch (e, st) {
      debugPrint('TenantMembership error: $e\n$st');
      return false;
    }
  }

  Future<void> _logClaimsSiExisten() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdTokenResult(false);
      final claims = token.claims ?? {};
      if (claims.containsKey('tenantId') || claims.containsKey('rol')) {
        debugPrint(
          'TenantClaims presentes tenantId=${claims['tenantId']} rol=${claims['rol']}',
        );
      }
    } catch (_) {}
  }
}
