import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Identificador corto y estable de este dispositivo (PC / celular).
/// Se usa para que remitos/compras no choquen el mismo número entre equipos.
class DeviceIdentity {
  DeviceIdentity._();

  static const _prefsKey = 'device_identity_tag_v1';
  static String? _cache;

  /// 4 caracteres A-Z0-9, persistente por instalación.
  static Future<String> shortTag() async {
    if (_cache != null && _cache!.isNotEmpty) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    var tag = prefs.getString(_prefsKey)?.trim().toUpperCase() ?? '';
    if (tag.length != 4) {
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rnd = Random.secure();
      tag = List.generate(4, (_) => alphabet[rnd.nextInt(alphabet.length)])
          .join();
      await prefs.setString(_prefsKey, tag);
    }
    _cache = tag;
    return tag;
  }
}
