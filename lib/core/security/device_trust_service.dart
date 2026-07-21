import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/backend_config_service.dart';
import '../config/device_identity.dart';
import '../firebase/firebase_auth_usuario_service.dart';
import '../firebase/firebase_bootstrap.dart';

/// Registro de dispositivos del tenant (Device Trust — Capacidad 1).
///
/// No sustituye App Check; aporta inventario de dispositivos conocidos
/// por empresa para soporte y auditoría.
class DeviceTrustService {
  DeviceTrustService._();

  static final DeviceTrustService instance = DeviceTrustService._();

  Future<void> registrarDispositivoActual() async {
    if (!FirebaseBootstrap.isReady) return;
    final uid = FirebaseAuthUsuarioService.instance.uidActual;
    if (uid == null || uid.isEmpty) return;

    final tenantId = BackendConfigService.instance.tenantId;
    if (tenantId.isEmpty) return;

    try {
      final tag = await DeviceIdentity.shortTag();
      final deviceId =
          '${tag}_${uid.length > 8 ? uid.substring(0, 8) : uid}'
              .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final ahora = DateTime.now().toUtc().toIso8601String();
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .collection('devices')
          .doc(deviceId)
          .set({
        'uid': uid,
        'deviceId': deviceId,
        'deviceTag': tag,
        'platform': defaultTargetPlatform.name,
        'actualizadoEn': ahora,
        'creadoEn': ahora,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('DeviceTrust registrar: $e');
    }
  }
}
