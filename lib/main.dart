import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/el_tata_app.dart';
import 'core/services/afip_service.dart';
import 'core/services/app_log.dart';
import 'core/services/branding_service.dart';
import 'core/services/document_numbering_service.dart';
import 'core/services/permisos_service.dart';
import 'core/services/sidebar_preferencias_service.dart';
import 'core/comms/local_notification_service.dart';
import 'core/comms/fcm_push_service.dart';
import 'core/config/backend_config_service.dart';
import 'core/config/platform_capabilities.dart';
import 'core/domain/domain_bootstrap.dart';
import 'core/events/producto_side_effects.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_safe_mode.dart';
import 'core/integrity/integrity_policy.dart';
import 'features/comunicaciones/whatsapp/whatsapp_catalog_service.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(appendAppLog('FlutterError: ${details.exceptionAsString()}'));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(appendAppLog('PlatformError: $error\n$stack'));
    return true;
  };

  await runZonedGuarded(() async {
    await appendAppLog('BOOT start');
    initializeThemeProvider();
    await BrandingService.instance.cargar();
    await SidebarPreferenciasService.instance.cargar();
    await DocumentNumberingService.instance.cargar();
    await AfipConfigService.instance.cargar();
    await BackendConfigService.instance.cargar();
    await IntegrityPolicy.instance.cargar();
    await FirebaseSafeMode.cargar();
    await LocalNotificationService.instance.init();

    // FCM background handler debe registrarse antes de runApp (Android).
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        BackendConfigService.instance.firebaseEnabled &&
        !FirebaseSafeMode.enabled) {
      try {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      } catch (e) {
        await appendAppLog('FCM background register: $e');
      }
    }

    const desktopPlatforms = {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    };

    // SQLite ANTES que cualquier otra cosa que use DB.
    if (!kIsWeb && desktopPlatforms.contains(defaultTargetPlatform)) {
      await appendAppLog('BOOT sqfliteFfiInit');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Firebase solo si el usuario lo activó (en Windows es opt-in).
    if (BackendConfigService.instance.firebaseEnabled &&
        !FirebaseSafeMode.enabled) {
      try {
        await appendAppLog('BOOT firebase init');
        await FirebaseBootstrap.initializeIfNeeded();
      } catch (e, st) {
        await appendAppLog('FirebaseInit: $e\n$st');
        await FirebaseSafeMode.activar();
      }
    } else {
      await appendAppLog(
        'BOOT firebase OFF '
        '(enabled=${BackendConfigService.instance.firebaseEnabled} '
        'safe=${FirebaseSafeMode.enabled} '
        'windows=${PlatformCapabilities.isWindowsDesktop})',
      );
    }

    await appendAppLog('BOOT permisos');
    try {
      DomainBootstrap.ensureInitialized();
      await PermisosService.instance.cargar();
    } catch (e, st) {
      await appendAppLog('Permisos cargar: $e\n$st');
    }

    // Plugins: hooks post-producto (WhatsApp Catalog, etc.).
    ProductoSideEffects.registerAfterSave(
      WhatsappCatalogService.instance.onProductoSideEffect,
    );

    await appendAppLog('BOOT runApp');
    runApp(const ElTataApp());
  }, (error, stack) {
    unawaited(appendAppLog('ZoneError: $error\n$stack'));
  });
}
