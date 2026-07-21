import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desbloqueo con huella / rostro / patrón / PIN del dispositivo (Android).
class BiometricAuthService {
  BiometricAuthService._();
  static final BiometricAuthService instance = BiometricAuthService._();

  static const _keyEnabled = 'biometric_unlock_enabled';
  static const _keyUserId = 'biometric_user_id';

  final LocalAuthentication _auth = LocalAuthentication();

  String? lastError;

  bool get esAndroidMovil => !kIsWeb && Platform.isAndroid;

  Future<bool> dispositivoSoporta() async {
    if (!esAndroidMovil) return false;
    try {
      final can = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return can || supported;
    } catch (e) {
      lastError = '$e';
      debugPrint('Biometric soporta: $e');
      return false;
    }
  }

  Future<bool> tieneHuellaOBiometria() async {
    if (!await dispositivoSoporta()) return false;
    try {
      final disponibles = await _auth.getAvailableBiometrics();
      return disponibles.isNotEmpty || await _auth.isDeviceSupported();
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

  /// Pide huella/rostro/patrón/PIN del dispositivo.
  Future<bool> autenticar({
    String motivo = 'Desbloqueá Tata.Manager',
  }) async {
    lastError = null;
    if (!await dispositivoSoporta()) {
      lastError = 'Este dispositivo no soporta biometría.';
      return false;
    }
    try {
      // Pequeña pausa: evita choque si acabamos de cerrar un diálogo.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final ok = await _auth.authenticate(
        localizedReason: motivo,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: false,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );
      if (!ok) {
        lastError =
            'No se confirmó la identidad. Probá de nuevo o usá el PIN/patrón del celular.';
      }
      return ok;
    } on PlatformException catch (e) {
      lastError = _mensajePlatform(e);
      debugPrint('Biometric PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      lastError = 'Error al verificar identidad: $e';
      debugPrint('Biometric auth: $e');
      return false;
    }
  }

  String _mensajePlatform(PlatformException e) {
    switch (e.code) {
      case 'NotAvailable':
      case 'NotEnrolled':
        return 'Configurá huella, rostro o PIN en Ajustes del celular.';
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return 'Biometría bloqueada. Desbloqueá el celular e intentá de nuevo.';
      case 'UserCancel':
      case 'Canceled':
        return 'Cancelaste la verificación.';
      case 'FragmentActivity':
      case 'no_fragment_activity':
        return 'Falta reiniciar la app tras la actualización (FragmentActivity).';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'No se pudo verificar la identidad (${e.code}).';
    }
  }
}
