import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desbloqueo con huella / biometría (Android principalmente).
class BiometricAuthService {
  BiometricAuthService._();
  static final BiometricAuthService instance = BiometricAuthService._();

  static const _keyEnabled = 'biometric_unlock_enabled';
  static const _keyUserId = 'biometric_user_id';

  final LocalAuthentication _auth = LocalAuthentication();

  bool get esAndroidMovil => !kIsWeb && Platform.isAndroid;

  Future<bool> dispositivoSoporta() async {
    if (!esAndroidMovil) return false;
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can || supported;
    } catch (e) {
      debugPrint('Biometric soporta: $e');
      return false;
    }
  }

  Future<bool> tieneHuellaOBiometria() async {
    if (!await dispositivoSoporta()) return false;
    try {
      final disponibles = await _auth.getAvailableBiometrics();
      return disponibles.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> estaActivada() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) == true &&
        prefs.getInt(_keyUserId) != null;
  }

  Future<int?> usuarioIdGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyEnabled) != true) return null;
    return prefs.getInt(_keyUserId);
  }

  Future<void> activarParaUsuario(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
    await prefs.setInt(_keyUserId, userId);
  }

  Future<void> desactivar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, false);
    await prefs.remove(_keyUserId);
  }

  /// Pide huella/rostro. Devuelve true si el usuario se autenticó.
  Future<bool> autenticar({
    String motivo = 'Desbloqueá Tata.Manager',
  }) async {
    if (!await dispositivoSoporta()) return false;
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric auth: $e');
      return false;
    }
  }
}
