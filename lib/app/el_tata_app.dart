import 'package:flutter/material.dart';

import '../core/theme/theme_provider.dart';
import '../features/auth/login_page.dart';

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
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(themeProvider.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LoginPage(),
    );
  }
}
