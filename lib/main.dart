import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'services/afip_service.dart';
import 'services/app_log.dart';
import 'services/branding_service.dart';
import 'services/document_numbering_service.dart';
import 'services/permisos_service.dart';
import 'services/sidebar_preferencias_service.dart';
import 'core/config/backend_config_service.dart';
import 'core/config/platform_capabilities.dart';
import 'core/domain/domain_bootstrap.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_safe_mode.dart';
import 'theme/theme_provider.dart';

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
    await FirebaseSafeMode.cargar();

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

    await appendAppLog('BOOT runApp');
    runApp(const ElTataApp());
  }, (error, stack) {
    unawaited(appendAppLog('ZoneError: $error\n$stack'));
  });
}

class ElTataApp extends StatefulWidget {
  const ElTataApp({super.key});

  @override
  State<ElTataApp> createState() => _ElTataAppState();
}

class _ElTataAppState extends State<ElTataApp> {
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tata.Manager',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.mode,
      home: const LoginPage(),
    );
  }
}
