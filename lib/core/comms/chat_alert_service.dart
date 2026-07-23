import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_notification_service.dart';

/// Alerta sonora + notificación del sistema cuando llega un mensaje/aviso.
class ChatAlertService {
  ChatAlertService._();
  static final ChatAlertService instance = ChatAlertService._();

  final AudioPlayer _player = AudioPlayer();
  int _ultimoMensajesSinLeer = 0;
  int _ultimoNotifSinLeer = 0;
  bool _listo = false;
  bool _audioListo = false;
  DateTime? _ultimoBeep;

  void marcarBaseline(int mensajesSinLeer, {int notifSinLeer = 0}) {
    _ultimoMensajesSinLeer = mensajesSinLeer;
    _ultimoNotifSinLeer = notifSinLeer;
    _listo = true;
  }

  /// Al detener el servicio: el próximo refresh solo fija baseline (sin beep).
  void reset() {
    _listo = false;
    _ultimoMensajesSinLeer = 0;
    _ultimoNotifSinLeer = 0;
  }

  Future<void> _asegurarAudio() async {
    if (_audioListo) return;
    try {
      // Android: sin esto BytesSource a menudo no suena (modo silencio / focus).
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await _player.setVolume(1.0);
      _audioListo = true;
    } catch (e) {
      debugPrint('ChatAlert audioContext: $e');
    }
  }

  /// Llama tras refrescar comunicaciones. Suena/muestra solo si suben no leídos.
  Future<void> onUnreadChanged(
    int mensajesSinLeer, {
    int notifSinLeer = 0,
    String? tituloMensaje,
    String? cuerpoMensaje,
    String? tituloNotif,
    String? cuerpoNotif,
  }) async {
    if (!_listo) {
      marcarBaseline(mensajesSinLeer, notifSinLeer: notifSinLeer);
      return;
    }
    final subioMsg = mensajesSinLeer > _ultimoMensajesSinLeer;
    final subioNotif = notifSinLeer > _ultimoNotifSinLeer;
    _ultimoMensajesSinLeer = mensajesSinLeer;
    _ultimoNotifSinLeer = notifSinLeer;
    if (!subioMsg && !subioNotif) return;

    final ahora = DateTime.now();
    final muySeguido = _ultimoBeep != null &&
        ahora.difference(_ultimoBeep!) < const Duration(milliseconds: 800);
    if (!muySeguido) {
      _ultimoBeep = ahora;
      await _beep();
    }

    if (subioMsg) {
      await LocalNotificationService.instance.show(
        titulo: (tituloMensaje ?? '').trim().isEmpty
            ? 'Mensaje nuevo'
            : tituloMensaje!.trim(),
        cuerpo: (cuerpoMensaje ?? '').trim().isEmpty
            ? 'Tenés un mensaje en Tata.Manager'
            : cuerpoMensaje!.trim(),
        payload: 'chat',
      );
    } else if (subioNotif) {
      await LocalNotificationService.instance.show(
        titulo: (tituloNotif ?? '').trim().isEmpty
            ? 'Aviso Tata.Manager'
            : tituloNotif!.trim(),
        cuerpo: (cuerpoNotif ?? '').trim().isEmpty
            ? 'Tenés una notificación nueva'
            : cuerpoNotif!.trim(),
        payload: 'notif',
      );
    }
  }

  Future<void> _beep() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await _asegurarAudio();
      await _player.stop();
      await _player.play(BytesSource(_wavBeep()));
    } catch (e) {
      debugPrint('ChatAlert beep: $e');
    }
  }

  /// WAV PCM 16-bit mono ~0.22s (tono más audible).
  Uint8List _wavBeep() {
    const sampleRate = 22050;
    const durationMs = 220;
    const freq = 980.0;
    final nSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = nSamples * 2;
    final out = BytesBuilder();

    void writeStr(String s) => out.add(s.codeUnits);
    void write32(int v) {
      out.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
    }

    void write16(int v) {
      out.add([v & 0xff, (v >> 8) & 0xff]);
    }

    writeStr('RIFF');
    write32(36 + dataSize);
    writeStr('WAVE');
    writeStr('fmt ');
    write32(16);
    write16(1); // PCM
    write16(1); // mono
    write32(sampleRate);
    write32(sampleRate * 2);
    write16(2);
    write16(16);
    writeStr('data');
    write32(dataSize);

    for (var i = 0; i < nSamples; i++) {
      final t = i / sampleRate;
      final env = i < 400
          ? i / 400.0
          : (i > nSamples - 400 ? (nSamples - i) / 400.0 : 1.0);
      final sample = (0.55 *
              env *
              math.sin(2 * math.pi * freq * t) *
              32767)
          .round()
          .clamp(-32768, 32767);
      write16(sample);
    }
    return out.toBytes();
  }
}
