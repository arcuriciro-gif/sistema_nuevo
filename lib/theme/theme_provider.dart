import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  Color _color = AppTheme.coloresDisponibles[0];
  String _fuente = 'Poppins';
  ThemeMode _mode = ThemeMode.system;

  Color get color => _color;
  String get fuente => _fuente;
  ThemeMode get mode => _mode;

  ThemeData get lightTheme => AppTheme.light(_color, _fuente);
  ThemeData get darkTheme => AppTheme.dark(_color, _fuente);

  ThemeProvider() {
    _cargar();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final colorIndex = prefs.getInt('themeColorIndex') ?? 0;
    final fuenteStr = prefs.getString('themeFuente') ?? 'Poppins';
    final modeStr = prefs.getString('themeMode') ?? 'system';

    final safeColorIndex = colorIndex.clamp(
      0,
      AppTheme.coloresDisponibles.length - 1,
    ).toInt();
    _color = AppTheme.coloresDisponibles[safeColorIndex];
    _fuente = AppTheme.fuentesDisponibles.contains(fuenteStr)
        ? fuenteStr
        : 'Poppins';
    _mode = modeStr == 'light'
        ? ThemeMode.light
        : modeStr == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setColor(Color c) async {
    _color = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColorIndex', AppTheme.coloresDisponibles.indexOf(c));
    notifyListeners();
  }

  Future<void> setFuente(String f) async {
    _fuente = f;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeFuente', f);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeMode',
      m == ThemeMode.light
          ? 'light'
          : m == ThemeMode.dark
              ? 'dark'
              : 'system',
    );
    notifyListeners();
  }
}

late final ThemeProvider themeProvider;

void initializeThemeProvider() {
  themeProvider = ThemeProvider();
}
