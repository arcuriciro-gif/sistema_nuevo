import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Evita crashes nativos de Firebase en Windows:
/// si la app murió a mitad de un login Firebase, el próximo arranque
/// entra en modo seguro (solo SQLite) hasta que el usuario lo reactive.
class FirebaseSafeMode {
  FirebaseSafeMode._();

  static const _prefsKey = 'firebase_safe_mode';
  static const _markerName = 'tata_firebase_login.marker';

  static bool _safeMode = false;
  static bool get enabled => _safeMode;

  static Future<File> _markerFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _markerName));
  }

  static Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _safeMode = prefs.getBool(_prefsKey) ?? false;

    final marker = await _markerFile();
    if (await marker.exists()) {
      _safeMode = true;
      await prefs.setBool(_prefsKey, true);
      try {
        await marker.delete();
      } catch (_) {}
      debugPrint(
        'Firebase Safe Mode ON: se detectó un cierre durante login Firebase.',
      );
    }
  }

  static Future<void> activar() async {
    _safeMode = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  static Future<void> desactivar() async {
    _safeMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, false);
    final marker = await _markerFile();
    if (await marker.exists()) {
      try {
        await marker.delete();
      } catch (_) {}
    }
  }

  static Future<void> marcarInicioLoginFirebase() async {
    final marker = await _markerFile();
    await marker.writeAsString(DateTime.now().toIso8601String());
  }

  static Future<void> marcarFinLoginFirebase() async {
    final marker = await _markerFile();
    if (await marker.exists()) {
      try {
        await marker.delete();
      } catch (_) {}
    }
  }
}
