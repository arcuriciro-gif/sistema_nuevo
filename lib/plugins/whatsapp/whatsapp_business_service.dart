import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../database/database_helper.dart';
import '../../models/cliente.dart';
import 'whatsapp_business_config.dart';
import 'whatsapp_message_log.dart';

enum WhatsappSendMode { api, deeplink, template }

class WhatsappSendResult {
  final bool ok;
  final WhatsappSendMode modo;
  final String? waMessageId;
  final String? error;
  final Uri? deeplink;

  const WhatsappSendResult({
    required this.ok,
    required this.modo,
    this.waMessageId,
    this.error,
    this.deeplink,
  });
}

/// Plugin de envío WhatsApp Business (Cloud API + fallback wa.me).
/// Fuera del core: no sync, no outbox.
class WhatsappBusinessService {
  WhatsappBusinessService._();
  static final WhatsappBusinessService instance = WhatsappBusinessService._();

  final config = WhatsappBusinessConfig.instance;

  Future<void> cargar() => config.cargar();

  /// Normaliza a dígitos internacionales (sin +).
  String normalizarTelefono(String raw, {String? countryCode}) {
    var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.startsWith('+')) d = d.substring(1);
    d = d.replaceAll(RegExp(r'\D'), '');
    final cc = (countryCode ?? config.defaultCountryCode).replaceAll(RegExp(r'\D'), '');
    if (cc.isNotEmpty && !d.startsWith(cc) && d.length <= 10) {
      // AR móvil: 15XXXXXXXX → 9 + área + número (simplificado: prefija país).
      if (cc == '54' && d.startsWith('15') && d.length >= 10) {
        d = '9${d.substring(2)}';
      }
      if (cc == '54' && d.length == 10 && !d.startsWith('9')) {
        d = '9$d';
      }
      d = '$cc$d';
    }
    return d;
  }

  String? telefonoDeCliente(Cliente c) {
    final w = c.whatsapp.trim();
    final t = c.telefono.trim();
    final raw = w.isNotEmpty ? w : t;
    if (raw.isEmpty) return null;
    final n = normalizarTelefono(raw);
    return n.isEmpty ? null : n;
  }

  Uri deeplinkUri(String telefonoDigits, String mensaje) {
    final q = mensaje.trim().isEmpty
        ? 'https://wa.me/$telefonoDigits'
        : 'https://wa.me/$telefonoDigits?text=${Uri.encodeComponent(mensaje)}';
    return Uri.parse(q);
  }

  Future<WhatsappSendResult> abrirDeeplink({
    required String telefonoDigits,
    required String mensaje,
    int? clienteId,
  }) async {
    final uri = deeplinkUri(telefonoDigits, mensaje);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    await _log(
      WhatsappMessageLog(
        clienteId: clienteId,
        telefono: telefonoDigits,
        cuerpo: mensaje,
        modo: 'deeplink',
        estado: ok ? 'abierto' : 'error',
        error: ok ? '' : 'No se pudo abrir WhatsApp',
        fecha: DateTime.now(),
      ),
    );
    return WhatsappSendResult(
      ok: ok,
      modo: WhatsappSendMode.deeplink,
      deeplink: uri,
      error: ok ? null : 'No se pudo abrir WhatsApp',
    );
  }

  /// Envía texto por Cloud API. Requiere ventana de 24h o fallará (usar template).
  Future<WhatsappSendResult> enviarTextoApi({
    required String telefonoDigits,
    required String mensaje,
    int? clienteId,
  }) async {
    await config.cargar();
    if (!config.listoParaApi) {
      return const WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.api,
        error: 'WhatsApp Business API no configurada',
      );
    }
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.phoneNumberId}/messages',
    );
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type': 'individual',
          'to': telefonoDigits,
          'type': 'text',
          'text': {'preview_url': false, 'body': mensaje},
        }),
      );
      final body = res.body;
      Map<String, dynamic> json = {};
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final msgId = _messageIdFrom(json);
        await _log(
          WhatsappMessageLog(
            clienteId: clienteId,
            telefono: telefonoDigits,
            cuerpo: mensaje,
            modo: 'api',
            estado: 'ok',
            waMessageId: msgId ?? '',
            fecha: DateTime.now(),
          ),
        );
        return WhatsappSendResult(
          ok: true,
          modo: WhatsappSendMode.api,
          waMessageId: msgId,
        );
      }
      final err = (json['error'] as Map?)?['message']?.toString() ??
          'HTTP ${res.statusCode}: $body';
      await _log(
        WhatsappMessageLog(
          clienteId: clienteId,
          telefono: telefonoDigits,
          cuerpo: mensaje,
          modo: 'api',
          estado: 'error',
          error: err,
          fecha: DateTime.now(),
        ),
      );
      return WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.api,
        error: err,
      );
    } catch (e) {
      debugPrint('WhatsApp API: $e');
      await _log(
        WhatsappMessageLog(
          clienteId: clienteId,
          telefono: telefonoDigits,
          cuerpo: mensaje,
          modo: 'api',
          estado: 'error',
          error: '$e',
          fecha: DateTime.now(),
        ),
      );
      return WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.api,
        error: '$e',
      );
    }
  }

  /// Template aprobado en Meta. [bodyParams] = variables {{1}}, {{2}}, …
  Future<WhatsappSendResult> enviarTemplateApi({
    required String telefonoDigits,
    required String templateName,
    String languageCode = 'es_AR',
    List<String> bodyParams = const [],
    int? clienteId,
    String cuerpoLog = '',
  }) async {
    await config.cargar();
    if (!config.listoParaApi) {
      return const WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.template,
        error: 'WhatsApp Business API no configurada',
      );
    }
    final components = <Map<String, dynamic>>[];
    if (bodyParams.isNotEmpty) {
      components.add({
        'type': 'body',
        'parameters': [
          for (final p in bodyParams) {'type': 'text', 'text': p},
        ],
      });
    }
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.phoneNumberId}/messages',
    );
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': telefonoDigits,
          'type': 'template',
          'template': {
            'name': templateName,
            'language': {'code': languageCode},
            if (components.isNotEmpty) 'components': components,
          },
        }),
      );
      final decoded = jsonDecode(res.body);
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final msgId = _messageIdFrom(json);
        await _log(
          WhatsappMessageLog(
            clienteId: clienteId,
            telefono: telefonoDigits,
            cuerpo: cuerpoLog.isEmpty ? 'template:$templateName' : cuerpoLog,
            modo: 'template',
            estado: 'ok',
            waMessageId: msgId ?? '',
            fecha: DateTime.now(),
          ),
        );
        return WhatsappSendResult(
          ok: true,
          modo: WhatsappSendMode.template,
          waMessageId: msgId,
        );
      }
      final err = (json['error'] as Map?)?['message']?.toString() ??
          'HTTP ${res.statusCode}';
      await _log(
        WhatsappMessageLog(
          clienteId: clienteId,
          telefono: telefonoDigits,
          cuerpo: 'template:$templateName',
          modo: 'template',
          estado: 'error',
          error: err,
          fecha: DateTime.now(),
        ),
      );
      return WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.template,
        error: err,
      );
    } catch (e) {
      return WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.template,
        error: '$e',
      );
    }
  }

  /// Intenta API si está lista; si falla o no hay config, abre wa.me.
  Future<WhatsappSendResult> enviarOAbrir({
    required String telefonoDigits,
    required String mensaje,
    int? clienteId,
    bool forzarDeeplink = false,
  }) async {
    await config.cargar();
    if (!forzarDeeplink && config.listoParaApi) {
      final api = await enviarTextoApi(
        telefonoDigits: telefonoDigits,
        mensaje: mensaje,
        clienteId: clienteId,
      );
      if (api.ok) return api;
      // Fallback a deeplink si la API falla (p. ej. fuera de ventana 24h).
      final dl = await abrirDeeplink(
        telefonoDigits: telefonoDigits,
        mensaje: mensaje,
        clienteId: clienteId,
      );
      return WhatsappSendResult(
        ok: dl.ok,
        modo: WhatsappSendMode.deeplink,
        deeplink: dl.deeplink,
        error: api.error,
      );
    }
    return abrirDeeplink(
      telefonoDigits: telefonoDigits,
      mensaje: mensaje,
      clienteId: clienteId,
    );
  }

  Future<WhatsappSendResult> enviarACliente({
    required Cliente cliente,
    required String mensaje,
    bool forzarDeeplink = false,
  }) async {
    final tel = telefonoDeCliente(cliente);
    if (tel == null) {
      return const WhatsappSendResult(
        ok: false,
        modo: WhatsappSendMode.deeplink,
        error: 'Cliente sin WhatsApp ni teléfono',
      );
    }
    return enviarOAbrir(
      telefonoDigits: tel,
      mensaje: mensaje,
      clienteId: cliente.id,
      forzarDeeplink: forzarDeeplink,
    );
  }

  Future<String?> probarConexion() async {
    await config.cargar();
    if (!config.listoParaApi) return 'Falta token o Phone Number ID';
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.phoneNumberId}'
      '?fields=display_phone_number,verified_name,quality_rating',
    );
    try {
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${config.accessToken}'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final num = json['display_phone_number'] ?? config.phoneNumberId;
        final name = json['verified_name'] ?? '';
        return 'OK · $num${name.toString().isEmpty ? '' : ' · $name'}';
      }
      try {
        final json = jsonDecode(res.body);
        if (json is Map) {
          final err = json['error'];
          if (err is Map && err['message'] != null) {
            return err['message'].toString();
          }
        }
      } catch (_) {}
      return 'HTTP ${res.statusCode}';
    } catch (e) {
      return '$e';
    }
  }

  String? _messageIdFrom(Map<String, dynamic> json) {
    final messages = json['messages'];
    if (messages is List && messages.isNotEmpty) {
      final first = messages.first;
      if (first is Map) return first['id']?.toString();
    }
    return null;
  }

  Future<void> _log(WhatsappMessageLog log) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert('wa_mensajes_log', log.toMap()..remove('id'));
    } catch (e) {
      debugPrint('wa log: $e');
    }
  }

  Future<List<WhatsappMessageLog>> listarLog({int limite = 50}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'wa_mensajes_log',
      orderBy: 'datetime(fecha) DESC',
      limit: limite,
    );
    return rows.map(WhatsappMessageLog.fromMap).toList();
  }
}
