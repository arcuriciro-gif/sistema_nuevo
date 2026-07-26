import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/authorization_service.dart';

/// Configuración base para futura integración AFIP/ARCA.
/// Hoy guarda datos y deja las facturas listas; la autorización real
/// se conectará cuando se carguen certificados.
class AfipConfigService {
  AfipConfigService._();
  static final AfipConfigService instance = AfipConfigService._();

  static const _keyEnabled = 'afipEnabled';
  static const _keyAmbiente = 'afipAmbiente';
  static const _keyPuntoVenta = 'afipPuntoVenta';
  static const _keyCuitEmisor = 'afipCuitEmisor';
  static const _keyCertPath = 'afipCertPath';
  static const _keyKeyPath = 'afipKeyPath';
  static const _keyPreciosIncluyenIva = 'afipPreciosIncluyenIva';

  bool enabled = false;
  /// 'homo' | 'prod'
  String ambiente = 'homo';
  int puntoVenta = 1;
  String cuitEmisor = '';
  String certPath = '';
  String keyPath = '';
  /// Si true, en Factura A los precios de lista ya traen IVA.
  bool preciosIncluyenIva = false;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_keyEnabled) ?? false;
    ambiente = prefs.getString(_keyAmbiente) ?? 'homo';
    puntoVenta = prefs.getInt(_keyPuntoVenta) ?? 1;
    cuitEmisor = prefs.getString(_keyCuitEmisor) ?? '';
    certPath = prefs.getString(_keyCertPath) ?? '';
    keyPath = prefs.getString(_keyKeyPath) ?? '';
    preciosIncluyenIva = prefs.getBool(_keyPreciosIncluyenIva) ?? false;
  }

  Future<void> guardar({
    required bool enabled,
    required String ambiente,
    required int puntoVenta,
    required String cuitEmisor,
    String? certPath,
    String? keyPath,
    bool? preciosIncluyenIva,
  }) async {
    AuthorizationService.instance.requireAdmin(operacion: 'configurar AFIP');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
    await prefs.setString(_keyAmbiente, ambiente);
    await prefs.setInt(_keyPuntoVenta, puntoVenta);
    await prefs.setString(_keyCuitEmisor, cuitEmisor);
    await prefs.setString(_keyCertPath, certPath ?? this.certPath);
    await prefs.setString(_keyKeyPath, keyPath ?? this.keyPath);
    if (preciosIncluyenIva != null) {
      await prefs.setBool(_keyPreciosIncluyenIva, preciosIncluyenIva);
      this.preciosIncluyenIva = preciosIncluyenIva;
    }
    this.enabled = enabled;
    this.ambiente = ambiente;
    this.puntoVenta = puntoVenta;
    this.cuitEmisor = cuitEmisor;
    if (certPath != null) this.certPath = certPath;
    if (keyPath != null) this.keyPath = keyPath;
  }

  bool get listoParaAutorizar =>
      enabled &&
      cuitEmisor.replaceAll('-', '').length >= 11 &&
      certPath.isNotEmpty &&
      keyPath.isNotEmpty;
}

class AfipAutorizacionResultado {
  final bool ok;
  final String estado;
  final String? cae;
  final DateTime? caeVencimiento;
  final String mensaje;

  AfipAutorizacionResultado({
    required this.ok,
    required this.estado,
    this.cae,
    this.caeVencimiento,
    required this.mensaje,
  });
}

/// Stub de servicio AFIP/ARCA. Cuando haya certificados, acá se conecta WSAA/WSFE.
class AfipService {
  AfipService._();
  static final AfipService instance = AfipService._();

  Future<AfipAutorizacionResultado> autorizarFactura({
    required String tipo,
    required String numero,
    required double total,
    String? clienteCuit,
  }) async {
    final cfg = AfipConfigService.instance;
    if (!cfg.enabled) {
      return AfipAutorizacionResultado(
        ok: true,
        estado: 'no_aplica',
        mensaje: 'AFIP desactivado: documento interno',
      );
    }
    if (!cfg.listoParaAutorizar) {
      return AfipAutorizacionResultado(
        ok: false,
        estado: 'pendiente_config',
        mensaje:
            'AFIP activado pero faltan CUIT emisor o certificados. '
            'No se puede confirmar la factura fiscal hasta completar la config.',
      );
    }
    // Placeholder: integración real WSAA/WSFE pendiente.
    // Mientras tanto NO autorizamos (ok:false sin CAE) — la UI debe bloquear.
    return AfipAutorizacionResultado(
      ok: false,
      estado: 'pendiente_afip',
      mensaje:
          'AFIP está activado pero la autorización electrónica aún no está '
          'conectada (faltan certificados WSAA/WSFE). '
          'Desactivá AFIP en Configuración para emitir documentos internos, '
          'o completá la integración antes de facturar.',
    );
  }
}
