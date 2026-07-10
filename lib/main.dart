import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'services/afip_service.dart';
import 'services/branding_service.dart';
import 'services/document_numbering_service.dart';
import 'services/permisos_service.dart';
import 'core/config/backend_config_service.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_safe_mode.dart';
import 'theme/theme_provider.dart';

Future<void> _appendCrashLog(String message) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tata_manager_error.log'));
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_appendCrashLog('FlutterError: ${details.exceptionAsString()}'));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_appendCrashLog('PlatformError: $error\n$stack'));
    return true;
  };

  await runZonedGuarded(() async {
    initializeThemeProvider();
    await BrandingService.instance.cargar();
    await DocumentNumberingService.instance.cargar();
    await AfipConfigService.instance.cargar();
    await BackendConfigService.instance.cargar();
    await FirebaseSafeMode.cargar();

    // En modo seguro no inicializamos Firebase: evita el crash nativo al login.
    if (!FirebaseSafeMode.enabled) {
      try {
        await FirebaseBootstrap.initializeIfNeeded();
      } catch (e, st) {
        debugPrint('Firebase init falló: $e');
        await _appendCrashLog('FirebaseInit: $e\n$st');
        await FirebaseSafeMode.activar();
      }
    } else {
      debugPrint('Arranque en Firebase Safe Mode (solo local).');
    }

    const desktopPlatforms = {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    };

    if (!kIsWeb && desktopPlatforms.contains(defaultTargetPlatform)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    await PermisosService.instance.cargar();
    runApp(const ElTataApp());
  }, (error, stack) {
    debugPrint('Zona error: $error');
    unawaited(_appendCrashLog('ZoneError: $error\n$stack'));
  });
}

class ElTataApp extends StatefulWidget {
  const ElTataApp({super.key});

  @override
  State<ElTataApp> createState() => _ElTataAppState();
}

class _ElTataAppState extends State<ElTataApp> {
  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
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
