import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/device_identity.dart';

/// Almacén ofuscado local (sin plugin nativo).
/// Mejor que texto plano en SharedPreferences; no reemplaza Keychain/Keystore.
class SecureLocalStore {
  SecureLocalStore._();
  static final SecureLocalStore instance = SecureLocalStore._();

  static const _prefix = 'sec1:';

  Future<List<int>> _keyBytes() async {
    final tag = await DeviceIdentity.shortTag();
    final material = 'tata.manager.v1|$tag|secure-local';
    return sha256.convert(utf8.encode(material)).bytes;
  }

  Future<String> encrypt(String plain) async {
    if (plain.isEmpty) return '';
    final key = await _keyBytes();
    final rnd = Random.secure();
    final iv = List<int>.generate(16, (_) => rnd.nextInt(256));
    final data = utf8.encode(plain);
    final out = <int>[];
    for (var i = 0; i < data.length; i++) {
      out.add(data[i] ^ key[i % key.length] ^ iv[i % iv.length]);
    }
    final payload = base64Encode([...iv, ...out]);
    return '$_prefix$payload';
  }

  Future<String> decrypt(String stored) async {
    if (stored.isEmpty) return '';
    if (!stored.startsWith(_prefix)) return stored; // legacy plaintext
    final raw = base64Decode(stored.substring(_prefix.length));
    if (raw.length < 17) return '';
    final iv = raw.sublist(0, 16);
    final data = raw.sublist(16);
    final key = await _keyBytes();
    final out = <int>[];
    for (var i = 0; i < data.length; i++) {
      out.add(data[i] ^ key[i % key.length] ^ iv[i % iv.length]);
    }
    return utf8.decode(out);
  }

  /// Migra valor plano de [prefsKey] a cifrado in-place.
  Future<String> loadMigrating(String prefsKey) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(prefsKey) ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith(_prefix)) return decrypt(raw);
    final enc = await encrypt(raw);
    await p.setString(prefsKey, enc);
    return raw;
  }

  Future<void> saveEncrypted(String prefsKey, String plain) async {
    final p = await SharedPreferences.getInstance();
    if (plain.isEmpty) {
      await p.remove(prefsKey);
      return;
    }
    await p.setString(prefsKey, await encrypt(plain));
  }
}
