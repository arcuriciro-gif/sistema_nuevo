import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'pages/login_page.dart';
import 'services/branding_service.dart';
import 'services/permisos_service.dart';
import 'core/config/backend_config_service.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/sync/firestore_sync_service.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeThemeProvider();
  await BrandingService.instance.cargar();
  await BackendConfigService.instance.cargar();
  await FirebaseBootstrap.initializeIfNeeded();

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
  await FirestoreSyncService.instance.start();
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
      title: 'EL TATA Manager',
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.mode,
      home: const LoginPage(),
    );
  }
}
