import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config_service.dart';
import '../config/platform_capabilities.dart';
import '../firebase/firebase_bootstrap.dart';
import '../../firebase_options.dart';
import '../../services/auth_service.dart';
import 'local_notification_service.dart';

/// Push FCM para alertas de comunicaciones con la app cerrada/background.
///
/// - Registra token en `tenants/{t}/fcm_tokens/{usuario}__{deviceId}`
/// - Muestra notificación local al recibir data/notification messages
/// - Encola `push_requests` al crear avisos (la Cloud Function los despacha)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final titulo = message.notification?.title ??
        message.data['titulo']?.toString() ??
        'Tata.Manager';
    final cuerpo = message.notification?.body ??
        message.data['cuerpo']?.toString() ??
        'Tenés un aviso nuevo';
    final payload = message.data['payload']?.toString() ?? 'notif';
    await LocalNotificationService.instance.show(
      titulo: titulo,
      cuerpo: cuerpo,
      payload: payload,
    );
  } catch (e) {
    debugPrint('FCM background: $e');
  }
}

class FcmPushService {
  FcmPushService._();
  static final FcmPushService instance = FcmPushService._();

  static const _prefsDeviceId = 'fcm_device_id_v1';
  bool _listo = false;
  String? _token;

  bool get soportado {
    if (kIsWeb) return false;
    // FCM push real: Android (iOS necesitaría APNs). Windows no recibe FCM.
    return !PlatformCapabilities.isWindowsDesktop && Platform.isAndroid;
  }

  Future<void> iniciar() async {
    if (_listo || !soportado) return;
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          _emitTap(initial);
        });
      }

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_persistirToken(t));
      });

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        await _persistirToken(token);
      }

      _listo = true;
      debugPrint('FCM listo (token=${_token != null})');
    } catch (e) {
      debugPrint('FcmPushService.iniciar: $e');
    }
  }

  Future<void> registrarUsuarioActual() async {
    if (!soportado || _token == null) return;
    await _persistirToken(_token!);
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final titulo = message.notification?.title ??
        message.data['titulo']?.toString() ??
        'Tata.Manager';
    final cuerpo = message.notification?.body ??
        message.data['cuerpo']?.toString() ??
        'Tenés un aviso nuevo';
    final payload = message.data['payload']?.toString() ?? 'notif';
    await LocalNotificationService.instance.show(
      titulo: titulo,
      cuerpo: cuerpo,
      payload: payload,
    );
  }

  void _onOpened(RemoteMessage message) => _emitTap(message);

  void _emitTap(RemoteMessage message) {
    final payload = message.data['payload']?.toString() ?? 'notif';
    final handler = LocalNotificationService.instance.onTap;
    if (handler != null) {
      handler(payload);
    }
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsDeviceId, id);
    }
    return id;
  }

  Future<void> _persistirToken(String token) async {
    final yo = AuthService.instance.currentUser?.usuario;
    if (yo == null || yo.isEmpty) return;
    if (!FirebaseBootstrap.isReady) return;
    try {
      final tenant = BackendConfigService.instance.tenantId;
      final deviceId = await _deviceId();
      final docId = '${yo}__$deviceId';
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenant)
          .collection('fcm_tokens')
          .doc(docId)
          .set({
        'usuario': yo,
        'token': token,
        'platform': 'android',
        'deviceId': deviceId,
        'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FCM persistir token: $e');
    }
  }

  /// Encola pedido de push (Cloud Function `onPushRequest` / `onNotificacion`).
  Future<void> encolarPush({
    required String usuarioDestino,
    required String titulo,
    required String cuerpo,
    String payload = 'notif',
    String? conversacionId,
    String? notificacionId,
  }) async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    // No push a uno mismo en el mismo dispositivo.
    if (usuarioDestino == AuthService.instance.currentUser?.usuario) return;
    try {
      final tenant = BackendConfigService.instance.tenantId;
      final id = notificacionId ?? const Uuid().v4();
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenant)
          .collection('push_requests')
          .doc(id)
          .set({
        'usuarioDestino': usuarioDestino,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'payload': payload,
        'conversacionId': ?conversacionId,
        'status': 'pending',
        'creadoEn': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('FCM encolarPush: $e');
    }
  }
}
