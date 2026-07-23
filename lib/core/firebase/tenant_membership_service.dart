import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth/rol_util.dart';
import '../config/backend_config_service.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';
import '../security/device_trust_service.dart';

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

  /// Quita membership (admin/owner). No borra la cuenta de Firebase Auth.
  Future<bool> eliminarMembresia(String uid) async {
    if (!FirebaseBootstrap.isReady) return false;
    final tenantId = BackendConfigService.instance.tenantId;
    if (tenantId.isEmpty || uid.trim().isEmpty) return false;
    try {
      final ref = _memberRef(tenantId, uid.trim());
      // Marca revocado antes del delete: el login rechaza activo=false.
      await ref.set({
        'activo': false,
        'revocadoEn': DateTime.now().toUtc().toIso8601String(),
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      await ref.delete();
      return true;
    } catch (e, st) {
      debugPrint('TenantMembership eliminar: $e\n$st');
      return false;
    }
  }

  /// ¿El uid tiene membresía activa en la empresa actual?
  Future<bool> esMiembroActivo(String uid) async {
    if (!FirebaseBootstrap.isReady) return false;
    final tenantId = BackendConfigService.instance.tenantId;
    if (tenantId.isEmpty || uid.trim().isEmpty) return false;
    try {
      final snap = await _memberRef(tenantId, uid.trim()).get();
      if (!snap.exists) return false;
      final data = snap.data() ?? {};
      if (data['activo'] == false) return false;
      return true;
    } catch (e) {
      debugPrint('TenantMembership esMiembroActivo: $e');
      return false;
    }
  }

  /// Admin invita / actualiza member de otro usuario (alta con rol).
  Future<bool> invitarOActualizarMiembro({
    required String uid,
    required String rol,
    String? email,
    String? usuario,
    bool activo = true,
  }) async {
    if (!FirebaseBootstrap.isReady) return false;
    final tenantId = BackendConfigService.instance.tenantId;
    final target = uid.trim();
    if (tenantId.isEmpty || target.isEmpty) return false;

    final ahora = DateTime.now().toUtc().toIso8601String();
    final rolNorm = RolUtil.normalizar(
      rol.trim().isEmpty ? RolUtil.empleado : rol.trim(),
    );

    try {
      await _memberRef(tenantId, target).set({
        'uid': target,
        'rol': rolNorm,
        'activo': activo,
        if (email != null && email.isNotEmpty) 'email': email,
        if (usuario != null && usuario.isNotEmpty) 'usuario': usuario,
        'actualizadoEn': ahora,
      }, SetOptions(merge: true));
      debugPrint(
        'TenantMembership: invitado uid=$target rol=$rolNorm activo=$activo',
      );
      return true;
    } catch (e, st) {
      debugPrint('TenantMembership invitar: $e\n$st');
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
