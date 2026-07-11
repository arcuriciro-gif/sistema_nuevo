import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'branding_service.dart';

/// Impresión térmica Bluetooth ESC/POS (58/80 mm).
/// No usa ubicación (apto para políticas de Google Play).
class ThermalPrintService {
  ThermalPrintService._();
  static final ThermalPrintService instance = ThermalPrintService._();

  static const _keyMac = 'thermal_printer_mac';
  static const _keyName = 'thermal_printer_name';

  String? _mac;
  String? _name;

  String? get printerMac => _mac;
  String? get printerName => _name;
  bool get tieneImpresoraGuardada => (_mac ?? '').isNotEmpty;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _mac = prefs.getString(_keyMac);
    _name = prefs.getString(_keyName);
  }

  Future<void> guardarImpresora({
    required String mac,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMac, mac);
    await prefs.setString(_keyName, name);
    _mac = mac;
    _name = name;
  }

  Future<void> olvidarImpresora() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMac);
    await prefs.remove(_keyName);
    _mac = null;
    _name = null;
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

  bool get plataformaSoportada {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS;
  }

  Future<bool> asegurarPermisos() async {
    if (!plataformaSoportada) return false;
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      final okConnect =
          statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final okScan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      // En Android < 12 el plugin puede no exigir estos; si fallan, igual
      // intentamos (dispositivos emparejados).
      if (!okConnect && !okScan) {
        final legacy = await PrintBluetoothThermal.isPermissionBluetoothGranted;
        return legacy;
      }
      return okConnect || okScan;
    }
    return true;
  }

  Future<bool> bluetoothEncendido() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<List<BluetoothInfo>> dispositivosEmparejados() async {
    await asegurarPermisos();
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> conectar([String? mac]) async {
    final target = (mac ?? _mac)?.trim() ?? '';
    if (target.isEmpty) return false;
    await asegurarPermisos();
    final already = await PrintBluetoothThermal.connectionStatus;
    if (already) return true;
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: target);
    } catch (_) {
      return false;
    }
  }

  Future<bool> desconectar() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (_) {
      return false;
    }
  }

  PaperSize _paperSize() {
    final papel = BrandingService.instance.papelPdf;
    if (papel == 'ticket_80') return PaperSize.mm80;
    return PaperSize.mm58;
  }

  /// Genera bytes ESC/POS de un ticket (remito / venta / presupuesto).
  Future<List<int>> generarTicket({
    required String tituloDocumento,
    required String numero,
    required String fechaIso,
    required String clienteNombre,
    required List<Map<String, dynamic>> items,
    required double total,
    double descuento = 0,
    String? observaciones,
    String? estadoPago,
  }) async {
    final branding = BrandingService.instance;
    final profile = await CapabilityProfile.load();
    final generator = Generator(_paperSize(), profile);
    final bytes = <int>[];

    bytes.addAll(generator.reset());
    bytes.addAll(generator.text(
      branding.nombre,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));
    if (branding.slogan.trim().isNotEmpty) {
      bytes.addAll(generator.text(
        branding.slogan,
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    if (branding.cuit.trim().isNotEmpty) {
      bytes.addAll(generator.text(
        'CUIT ${branding.cuit}',
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    if (branding.direccionFiscal.trim().isNotEmpty) {
      bytes.addAll(generator.text(
        branding.direccionFiscal,
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(
      tituloDocumento,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.text('Nº $numero'));
    bytes.addAll(generator.text(_fmtFecha(fechaIso)));
    bytes.addAll(generator.text('Cliente: $clienteNombre'));
    if ((estadoPago ?? '').trim().isNotEmpty) {
      bytes.addAll(generator.text('Pago: ${estadoPago!.trim()}'));
    }
    bytes.addAll(generator.hr());

    for (final item in items) {
      final desc = (item['descripcion'] ?? '').toString();
      final cant = (item['cantidad'] as num?)?.toDouble() ?? 0;
      final precio = (item['precio'] as num?)?.toDouble() ??
          (item['precioUnitario'] as num?)?.toDouble() ??
          0;
      final sub = (item['subtotal'] as num?)?.toDouble() ?? (cant * precio);
      bytes.addAll(generator.text(desc));
      bytes.addAll(generator.row([
        PosColumn(
          text: '${_fmtNum(cant)} x \$${_fmtMoney(precio)}',
          width: 7,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: '\$${_fmtMoney(sub)}',
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(generator.hr());
    if (descuento > 0.009) {
      bytes.addAll(generator.row([
        PosColumn(text: 'Descuento', width: 7),
        PosColumn(
          text: '${_fmtMoney(descuento)}%',
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }
    bytes.addAll(generator.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: '\$${_fmtMoney(total)}',
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]));

    if ((observaciones ?? '').trim().isNotEmpty) {
      bytes.addAll(generator.hr());
      bytes.addAll(generator.text('Obs: ${observaciones!.trim()}'));
    }

    final pie = branding.piePdf.trim().isNotEmpty
        ? branding.piePdf.trim()
        : 'Gracias por su compra';
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(
      pie,
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<bool> imprimirBytes(List<int> bytes) async {
    if (bytes.isEmpty) return false;
    final connected = await conectar();
    if (!connected) return false;
    try {
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  Future<bool> imprimirTicket({
    required String tituloDocumento,
    required String numero,
    required String fechaIso,
    required String clienteNombre,
    required List<Map<String, dynamic>> items,
    required double total,
    double descuento = 0,
    String? observaciones,
    String? estadoPago,
  }) async {
    final bytes = await generarTicket(
      tituloDocumento: tituloDocumento,
      numero: numero,
      fechaIso: fechaIso,
      clienteNombre: clienteNombre,
      items: items,
      total: total,
      descuento: descuento,
      observaciones: observaciones,
      estadoPago: estadoPago,
    );
    return imprimirBytes(bytes);
  }

  String _fmtFecha(String iso) {
    final d = DateTime.tryParse(iso) ?? DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _fmtMoney(double v) => v.toStringAsFixed(2);
  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
