import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones del sistema (bandeja Android / Windows) con título y cuerpo.
///
/// Payload:
/// - `chat:<conversacionId>` → abrir ese chat
/// - `notif` → abrir lista de notificaciones
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _listo = false;
  int _seq = 0;

  /// Callback registrado por MainShell / app.
  void Function(String payload)? onTap;

  static const _androidChannel = AndroidNotificationChannel(
    'tata_manager_avisos',
    'Avisos Tata.Manager',
    description: 'Mensajes internos y avisos de la app',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_listo || kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const windowsInit = WindowsInitializationSettings(
        appName: 'Tata.Manager',
        appUserModelId: 'MatiasArcuri.TataManager.Desktop.1',
        guid: 'a7e4c2b1-9f3d-4e8a-b6c5-1d2e3f4a5b6c',
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        windows: windowsInit,
      );
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onResponse,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_androidChannel);
      await android?.requestNotificationsPermission();

      // Si abrieron la app tocando una notificación (app cerrada).
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        // Diferir: el shell todavía no registró onTap.
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          _emitTap(payload);
        });
      }

      _listo = true;
    } catch (e) {
      debugPrint('LocalNotificationService.init: $e');
    }
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _emitTap(payload);
  }

  void _emitTap(String payload) {
    final handler = onTap;
    if (handler != null) {
      handler(payload);
    } else {
      debugPrint('LocalNotification tap sin handler: $payload');
    }
  }

  Future<void> show({
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    if (kIsWeb) return;
    await init();
    if (!_listo) return;

    final title = titulo.trim().isEmpty ? 'Tata.Manager' : titulo.trim();
    final body = cuerpo.trim().isEmpty ? 'Tenés un aviso nuevo' : cuerpo.trim();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
      ),
      windows: const WindowsNotificationDetails(),
    );

    try {
      _seq += 1;
      await _plugin.show(
        id: _seq,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('LocalNotificationService.show: $e');
    }
  }

  bool get soportado {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
