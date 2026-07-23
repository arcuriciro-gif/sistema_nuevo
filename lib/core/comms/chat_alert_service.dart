import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Alerta sonora cuando llega un mensaje de chat (sin tocar sync).
class ChatAlertService {
  ChatAlertService._();
  static final ChatAlertService instance = ChatAlertService._();

  final AudioPlayer _player = AudioPlayer();
  int _ultimoMensajesSinLeer = 0;
  bool _listo = false;
  DateTime? _ultimoBeep;

  void marcarBaseline(int mensajesSinLeer) {
    _ultimoMensajesSinLeer = mensajesSinLeer;
    _listo = true;
  }

  /// Al detener el servicio: el próximo refresh solo fija baseline (sin beep).
  void reset() {
    _listo = false;
    _ultimoMensajesSinLeer = 0;
  }

  /// Llama tras refrescar comunicaciones. Suena solo si suben los no leídos.
  Future<void> onUnreadChanged(int mensajesSinLeer) async {
    if (!_listo) {
      marcarBaseline(mensajesSinLeer);
      return;
    }
    final subio = mensajesSinLeer > _ultimoMensajesSinLeer;
    _ultimoMensajesSinLeer = mensajesSinLeer;
    if (!subio) return;

    final ahora = DateTime.now();
    if (_ultimoBeep != null &&
        ahora.difference(_ultimoBeep!) < const Duration(milliseconds: 800)) {
      return;
    }
    _ultimoBeep = ahora;
    await _beep();
  }

  Future<void> _beep() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      await _player.stop();
      await _player.play(BytesSource(_wavBeep()));
    } catch (e) {
      debugPrint('ChatAlert beep: $e');
    }
  }

  /// WAV PCM 16-bit mono ~0.18s (tono corto).
  Uint8List _wavBeep() {
    const sampleRate = 22050;
    const durationMs = 180;
    const freq = 880.0;
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
      final sample = (0.35 *
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
