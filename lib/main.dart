import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'services/afip_service.dart';
import 'services/branding_service.dart';
import 'services/document_numbering_service.dart';
import 'services/permisos_service.dart';
import 'core/config/backend_config_service.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    initializeThemeProvider();
  } catch (e) {
    debugPrint('Theme init: $e');
  }

  try {
    await BrandingService.instance.cargar();
  } catch (e) {
    debugPrint('Branding init: $e');
  }

  try {
    await DocumentNumberingService.instance.cargar();
  } catch (e) {
    debugPrint('DocumentNumbering init: $e');
  }

  try {
    await AfipConfigService.instance.cargar();
  } catch (e) {
    debugPrint('Afip init: $e');
  }

  try {
    await BackendConfigService.instance.cargar();
  } catch (e) {
    debugPrint('BackendConfig init: $e');
  }

  try {
    await FirebaseBootstrap.initializeIfNeeded();
  } catch (e) {
    debugPrint('Firebase bootstrap: $e');
  }

  const desktopPlatforms = {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  };

  if (!kIsWeb && desktopPlatforms.contains(defaultTargetPlatform)) {
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    } catch (e) {
      debugPrint('SQLite FFI init: $e');
    }
  }

  try {
    await PermisosService.instance.cargar();
  } catch (e) {
    debugPrint('Permisos init: $e');
  }

  // Firestore sync starts after Firebase Auth login (rules require request.auth).
  runApp(const ElTataApp());
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
