import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/media_path.dart';
import '../core/sync/media_sync_service.dart';

class BrandingService extends ChangeNotifier {
  static const _keyNombre = 'brandNombre';
  static const _keySlogan = 'brandSlogan';
  static const _keyTelefono = 'brandTelefono';
  static const _keyDireccion = 'brandDireccion';
  static const _keyEmail = 'brandEmail';
  static const _keySitioWeb = 'brandSitioWeb';
  static const _keyWhatsapp = 'brandWhatsapp';
  static const _keyInstagram = 'brandInstagram';
  static const _keyFacebook = 'brandFacebook';
  static const _keyLogo = 'brandLogoPath';
  static const _keyIcono = 'brandIconoPath';
  static const _keyMoneda = 'brandMoneda';
  static const _keyFormatoFecha = 'brandFormatoFecha';
  static const _keyCuit = 'brandCuit';
  static const _keyIngresosBrutos = 'brandIngresosBrutos';
  static const _keyCondicionIva = 'brandCondicionIva';
  static const _keyDireccionFiscal = 'brandDireccionFiscal';
  static const _keyEncabezadoPdf = 'brandEncabezadoPdf';
  static const _keyPiePdf = 'brandPiePdf';
  static const _keyColorPdf = 'brandColorPdf';
  static const _keyPdfBlancoNegro = 'brandPdfBlancoNegro';
  static const colorPdfTransparente = 'TRANSPARENT';

  /// Paleta sugerida para encabezado de PDF (hex sin #).
  static const List<({String hex, String nombre})> paletaColoresPdf = [
    (hex: 'FF7A00', nombre: 'Naranja'),
    (hex: 'E53935', nombre: 'Rojo'),
    (hex: '8E24AA', nombre: 'Violeta'),
    (hex: '1E88E5', nombre: 'Azul'),
    (hex: '00897B', nombre: 'Verde agua'),
    (hex: '43A047', nombre: 'Verde'),
    (hex: '6D4C41', nombre: 'Marrón'),
    (hex: '37474F', nombre: 'Grafito'),
    (hex: '212121', nombre: 'Negro'),
  ];
  static const _keyPapelPdf = 'brandPapelPdf';
  static const _keyMargenPdf = 'brandMargenPdf';
  static const _keyFirma = 'brandFirmaPath';
  static const _keySello = 'brandSelloPath';
  static const _keyMostrarFirma = 'brandMostrarFirma';
  static const _keyMostrarSello = 'brandMostrarSello';
  static const _keyMostrarEstadoPago = 'brandMostrarEstadoPago';
  static const _keyLeyendaLegal = 'brandLeyendaLegal';
  static const _keyDiasVencimiento = 'brandDiasVencimiento';

  static final BrandingService instance = BrandingService._();
  BrandingService._();

  String nombre = 'Tata.Manager';
  String slogan = 'Gestión de stock, ventas y más';
  String telefono = '';
  String direccion = '';
  String email = '';
  String sitioWeb = '';
  String whatsapp = '';
  String instagram = '';
  String facebook = '';
  String logoPath = '';
  /// Icono visible dentro de la app (login, menú, etc.).
  String iconoPath = '';
  String moneda = r'$';
  String formatoFecha = 'dd/MM/yyyy';
  String cuit = '';
  String ingresosBrutos = '';
  String condicionIva = '';
  String direccionFiscal = '';
  String encabezadoPdf = '';
  String piePdf = '';
  /// Hex sin #, ej. FF7A00. Usar [colorPdfTransparente] para sin fondo.
  String colorPdf = 'FF7A00';
  /// Impresión/exportación en blanco y negro (encabezado transparente).
  bool pdfBlancoNegro = false;
  /// 'a4' | 'ticket_80' | 'ticket_58'
  String papelPdf = 'a4';
  /// Márgenes en mm
  double margenPdfMm = 10;
  String firmaPath = '';
  String selloPath = '';
  bool mostrarFirma = true;
  bool mostrarSello = true;
  bool mostrarEstadoPago = true;
  String leyendaLegal = '';
  /// Días por defecto para vencimiento de cuenta corriente.
  int diasVencimiento = 30;

  /// Imagen preferida para UI: icono si existe, si no logo.
  String get imagenUiPath =>
      iconoPath.isNotEmpty ? iconoPath : logoPath;

  bool get encabezadoPdfTransparente =>
      pdfBlancoNegro ||
      colorPdf.toUpperCase() == colorPdfTransparente ||
      colorPdf.trim().isEmpty;

  static String normalizarColorPdf(String raw) {
    final limpio = raw.replaceAll('#', '').trim().toUpperCase();
    if (limpio == colorPdfTransparente || limpio == 'NONE' || limpio == 'NULL') {
      return colorPdfTransparente;
    }
    if (limpio.length == 6 && RegExp(r'^[0-9A-F]{6}$').hasMatch(limpio)) {
      return limpio;
    }
    if (limpio.length == 8 && RegExp(r'^[0-9A-F]{8}$').hasMatch(limpio)) {
      return limpio.substring(2); // descarta alpha AA RR GG BB → RRGGBB
    }
    return 'FF7A00';
  }

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    nombre = prefs.getString(_keyNombre) ?? 'Tata.Manager';
    slogan = prefs.getString(_keySlogan) ?? 'Gestión de stock, ventas y más';
    telefono = prefs.getString(_keyTelefono) ?? '';
    direccion = prefs.getString(_keyDireccion) ?? '';
    email = prefs.getString(_keyEmail) ?? '';
    sitioWeb = prefs.getString(_keySitioWeb) ?? '';
    whatsapp = prefs.getString(_keyWhatsapp) ?? '';
    instagram = prefs.getString(_keyInstagram) ?? '';
    facebook = prefs.getString(_keyFacebook) ?? '';
    logoPath = prefs.getString(_keyLogo) ?? '';
    iconoPath = prefs.getString(_keyIcono) ?? '';
    moneda = prefs.getString(_keyMoneda) ?? r'$';
    formatoFecha = prefs.getString(_keyFormatoFecha) ?? 'dd/MM/yyyy';
    cuit = prefs.getString(_keyCuit) ?? '';
    ingresosBrutos = prefs.getString(_keyIngresosBrutos) ?? '';
    condicionIva = prefs.getString(_keyCondicionIva) ?? '';
    direccionFiscal = prefs.getString(_keyDireccionFiscal) ?? '';
    encabezadoPdf = prefs.getString(_keyEncabezadoPdf) ?? '';
    piePdf = prefs.getString(_keyPiePdf) ?? '';
    colorPdf = normalizarColorPdf(prefs.getString(_keyColorPdf) ?? 'FF7A00');
    pdfBlancoNegro = prefs.getBool(_keyPdfBlancoNegro) ?? false;
    papelPdf = prefs.getString(_keyPapelPdf) ?? 'a4';
    margenPdfMm = prefs.getDouble(_keyMargenPdf) ?? 10;
    firmaPath = prefs.getString(_keyFirma) ?? '';
    selloPath = prefs.getString(_keySello) ?? '';
    mostrarFirma = prefs.getBool(_keyMostrarFirma) ?? true;
    mostrarSello = prefs.getBool(_keyMostrarSello) ?? true;
    mostrarEstadoPago = prefs.getBool(_keyMostrarEstadoPago) ?? true;
    leyendaLegal = prefs.getString(_keyLeyendaLegal) ?? '';
    diasVencimiento = prefs.getInt(_keyDiasVencimiento) ?? 30;
    notifyListeners();
  }

  /// Copia la imagen a almacenamiento permanente de la app.
  Future<String> persistirImagen(String sourcePath, String nombreBase) async {
    final dir = await getApplicationDocumentsDirectory();
    final brandingDir = Directory(p.join(dir.path, 'branding'));
    if (!await brandingDir.exists()) {
      await brandingDir.create(recursive: true);
    }
    final ext = p.extension(sourcePath).isEmpty ? '.png' : p.extension(sourcePath);
    final dest = p.join(brandingDir.path, '$nombreBase$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<void> guardar({
    required String nombre,
    required String slogan,
    required String telefono,
    required String direccion,
    required String logoPath,
    String? iconoPath,
    String? email,
    String? sitioWeb,
    String? whatsapp,
    String? instagram,
    String? facebook,
    String? moneda,
    String? formatoFecha,
    String? cuit,
    String? ingresosBrutos,
    String? condicionIva,
    String? direccionFiscal,
    String? encabezadoPdf,
    String? piePdf,
    String? colorPdf,
    bool? pdfBlancoNegro,
    String? papelPdf,
    double? margenPdfMm,
    String? firmaPath,
    String? selloPath,
    bool? mostrarFirma,
    bool? mostrarSello,
    bool? mostrarEstadoPago,
    String? leyendaLegal,
    int? diasVencimiento,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre);
    await prefs.setString(_keySlogan, slogan);
    await prefs.setString(_keyTelefono, telefono);
    await prefs.setString(_keyDireccion, direccion);
    await prefs.setString(_keyLogo, logoPath);
    await prefs.setString(_keyIcono, iconoPath ?? this.iconoPath);
    await prefs.setString(_keyEmail, email ?? this.email);
    await prefs.setString(_keySitioWeb, sitioWeb ?? this.sitioWeb);
    await prefs.setString(_keyWhatsapp, whatsapp ?? this.whatsapp);
    await prefs.setString(_keyInstagram, instagram ?? this.instagram);
    await prefs.setString(_keyFacebook, facebook ?? this.facebook);
    await prefs.setString(_keyMoneda, moneda ?? this.moneda);
    await prefs.setString(_keyFormatoFecha, formatoFecha ?? this.formatoFecha);
    await prefs.setString(_keyCuit, cuit ?? this.cuit);
    await prefs.setString(
        _keyIngresosBrutos, ingresosBrutos ?? this.ingresosBrutos);
    await prefs.setString(_keyCondicionIva, condicionIva ?? this.condicionIva);
    await prefs.setString(
        _keyDireccionFiscal, direccionFiscal ?? this.direccionFiscal);
    await prefs.setString(
        _keyEncabezadoPdf, encabezadoPdf ?? this.encabezadoPdf);
    await prefs.setString(_keyPiePdf, piePdf ?? this.piePdf);
    await prefs.setString(
      _keyColorPdf,
      normalizarColorPdf(colorPdf ?? this.colorPdf),
    );
    await prefs.setBool(
      _keyPdfBlancoNegro,
      pdfBlancoNegro ?? this.pdfBlancoNegro,
    );
    await prefs.setString(_keyPapelPdf, papelPdf ?? this.papelPdf);
    await prefs.setDouble(_keyMargenPdf, margenPdfMm ?? this.margenPdfMm);
    await prefs.setString(_keyFirma, firmaPath ?? this.firmaPath);
    await prefs.setString(_keySello, selloPath ?? this.selloPath);
    await prefs.setBool(_keyMostrarFirma, mostrarFirma ?? this.mostrarFirma);
    await prefs.setBool(_keyMostrarSello, mostrarSello ?? this.mostrarSello);
    await prefs.setBool(
        _keyMostrarEstadoPago, mostrarEstadoPago ?? this.mostrarEstadoPago);
    await prefs.setString(_keyLeyendaLegal, leyendaLegal ?? this.leyendaLegal);
    await prefs.setInt(
        _keyDiasVencimiento, diasVencimiento ?? this.diasVencimiento);

    this.nombre = nombre;
    this.slogan = slogan;
    this.telefono = telefono;
    this.direccion = direccion;
    this.logoPath = logoPath;
    if (iconoPath != null) this.iconoPath = iconoPath;
    if (email != null) this.email = email;
    if (sitioWeb != null) this.sitioWeb = sitioWeb;
    if (whatsapp != null) this.whatsapp = whatsapp;
    if (instagram != null) this.instagram = instagram;
    if (facebook != null) this.facebook = facebook;
    if (moneda != null) this.moneda = moneda;
    if (formatoFecha != null) this.formatoFecha = formatoFecha;
    if (cuit != null) this.cuit = cuit;
    if (ingresosBrutos != null) this.ingresosBrutos = ingresosBrutos;
    if (condicionIva != null) this.condicionIva = condicionIva;
    if (direccionFiscal != null) this.direccionFiscal = direccionFiscal;
    if (encabezadoPdf != null) this.encabezadoPdf = encabezadoPdf;
    if (piePdf != null) this.piePdf = piePdf;
    if (colorPdf != null) this.colorPdf = normalizarColorPdf(colorPdf);
    if (pdfBlancoNegro != null) this.pdfBlancoNegro = pdfBlancoNegro;
    if (papelPdf != null) this.papelPdf = papelPdf;
    if (margenPdfMm != null) this.margenPdfMm = margenPdfMm;
    if (firmaPath != null) this.firmaPath = firmaPath;
    if (selloPath != null) this.selloPath = selloPath;
    if (mostrarFirma != null) this.mostrarFirma = mostrarFirma;
    if (mostrarSello != null) this.mostrarSello = mostrarSello;
    if (mostrarEstadoPago != null) this.mostrarEstadoPago = mostrarEstadoPago;
    if (leyendaLegal != null) this.leyendaLegal = leyendaLegal;
    if (diasVencimiento != null) this.diasVencimiento = diasVencimiento;
    notifyListeners();
  }

  /// Payload para Firestore (URLs de logo/icono, no paths locales).
  Map<String, dynamic> toFirestoreMap({
    String? logoUrl,
    String? iconoUrl,
  }) {
    return {
      'nombre': nombre,
      'slogan': slogan,
      'telefono': telefono,
      'direccion': direccion,
      'email': email,
      'sitioWeb': sitioWeb,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'facebook': facebook,
      'moneda': moneda,
      'formatoFecha': formatoFecha,
      'cuit': cuit,
      'ingresosBrutos': ingresosBrutos,
      'condicionIva': condicionIva,
      'direccionFiscal': direccionFiscal,
      'encabezadoPdf': encabezadoPdf,
      'piePdf': piePdf,
      'colorPdf': colorPdf,
      'pdfBlancoNegro': pdfBlancoNegro,
      'papelPdf': papelPdf,
      'margenPdfMm': margenPdfMm,
      'mostrarFirma': mostrarFirma,
      'mostrarSello': mostrarSello,
      'mostrarEstadoPago': mostrarEstadoPago,
      'leyendaLegal': leyendaLegal,
      'diasVencimiento': diasVencimiento,
      'logoUrl': logoUrl ?? (esUrlRemota(logoPath) ? logoPath : ''),
      'iconoUrl': iconoUrl ?? (esUrlRemota(iconoPath) ? iconoPath : ''),
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Sube logo/icono locales a Storage y arma el mapa para la nube.
  Future<Map<String, dynamic>> prepararPayloadNube() async {
    final media = MediaSyncService.instance;
    final tenant = media.tenantId;
    String logoUrl = esUrlRemota(logoPath) ? logoPath : '';
    String iconoUrl = esUrlRemota(iconoPath) ? iconoPath : '';

    if (logoPath.isNotEmpty && !esUrlRemota(logoPath)) {
      final f = File(logoPath);
      if (await f.exists()) {
        final ext =
            p.extension(logoPath).isEmpty ? '.jpg' : p.extension(logoPath);
        final url = await media.subirArchivo(
          storagePath:
              'tenants/$tenant/branding/logo_${const Uuid().v4()}$ext',
          file: f,
          contentType: 'image/jpeg',
        );
        if (url != null) logoUrl = url;
      }
    }
    if (iconoPath.isNotEmpty && !esUrlRemota(iconoPath)) {
      final f = File(iconoPath);
      if (await f.exists()) {
        final ext =
            p.extension(iconoPath).isEmpty ? '.jpg' : p.extension(iconoPath);
        final url = await media.subirArchivo(
          storagePath:
              'tenants/$tenant/branding/icono_${const Uuid().v4()}$ext',
          file: f,
          contentType: 'image/jpeg',
        );
        if (url != null) iconoUrl = url;
      }
    }

    return toFirestoreMap(logoUrl: logoUrl, iconoUrl: iconoUrl);
  }

  Future<String?> _descargarImagen(String url, String nombreBase) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final dir = await getApplicationDocumentsDirectory();
      final brandingDir = Directory(p.join(dir.path, 'branding'));
      if (!await brandingDir.exists()) {
        await brandingDir.create(recursive: true);
      }
      var ext = p.extension(Uri.parse(url).path);
      if (ext.isEmpty || ext.length > 5) ext = '.jpg';
      final dest = p.join(brandingDir.path, '$nombreBase$ext');
      await File(dest).writeAsBytes(res.bodyBytes);
      return dest;
    } catch (e) {
      debugPrint('Branding descargar imagen: $e');
      return null;
    }
  }

  /// Aplica branding remoto (textos + logo/icono por URL → cache local).
  Future<void> aplicarDesdeFirestore(Map<String, dynamic> data) async {
    String s(String key, [String def = '']) {
      final v = data[key]?.toString();
      if (v == null || v.isEmpty) return def;
      return v;
    }

    final logoUrl = s('logoUrl');
    final iconoUrl = s('iconoUrl');

    var nuevoLogo = logoPath;
    var nuevoIcono = iconoPath;

    if (logoUrl.isNotEmpty && esUrlRemota(logoUrl)) {
      final local = await _descargarImagen(logoUrl, 'logo_sync');
      if (local != null) nuevoLogo = local;
    }
    if (iconoUrl.isNotEmpty && esUrlRemota(iconoUrl)) {
      final local = await _descargarImagen(iconoUrl, 'icono_sync');
      if (local != null) nuevoIcono = local;
    }

    await guardar(
      nombre: s('nombre', nombre),
      slogan: s('slogan', slogan),
      telefono: s('telefono', telefono),
      direccion: s('direccion', direccion),
      logoPath: nuevoLogo,
      iconoPath: nuevoIcono,
      email: s('email', email),
      sitioWeb: s('sitioWeb', sitioWeb),
      whatsapp: s('whatsapp', whatsapp),
      instagram: s('instagram', instagram),
      facebook: s('facebook', facebook),
      moneda: s('moneda', moneda),
      formatoFecha: s('formatoFecha', formatoFecha),
      cuit: s('cuit', cuit),
      ingresosBrutos: s('ingresosBrutos', ingresosBrutos),
      condicionIva: s('condicionIva', condicionIva),
      direccionFiscal: s('direccionFiscal', direccionFiscal),
      encabezadoPdf: s('encabezadoPdf', encabezadoPdf),
      piePdf: s('piePdf', piePdf),
      colorPdf: s('colorPdf', colorPdf),
      pdfBlancoNegro: data['pdfBlancoNegro'] is bool
          ? data['pdfBlancoNegro'] as bool
          : pdfBlancoNegro,
      papelPdf: s('papelPdf', papelPdf),
      margenPdfMm: (data['margenPdfMm'] as num?)?.toDouble() ?? margenPdfMm,
      mostrarFirma: data['mostrarFirma'] is bool
          ? data['mostrarFirma'] as bool
          : mostrarFirma,
      mostrarSello: data['mostrarSello'] is bool
          ? data['mostrarSello'] as bool
          : mostrarSello,
      mostrarEstadoPago: data['mostrarEstadoPago'] is bool
          ? data['mostrarEstadoPago'] as bool
          : mostrarEstadoPago,
      leyendaLegal: s('leyendaLegal', leyendaLegal),
      diasVencimiento:
          (data['diasVencimiento'] as num?)?.toInt() ?? diasVencimiento,
    );
  }

  Future<void> guardarPlantilla({
    required String encabezadoPdf,
    required String piePdf,
    required String colorPdf,
    required String papelPdf,
    required double margenPdfMm,
    required String firmaPath,
    required String selloPath,
    required bool mostrarFirma,
    required bool mostrarSello,
    required bool mostrarEstadoPago,
    required String leyendaLegal,
    bool? pdfBlancoNegro,
    String? logoPath,
    int? diasVencimiento,
  }) {
    return guardar(
      nombre: nombre,
      slogan: slogan,
      telefono: telefono,
      direccion: direccion,
      logoPath: logoPath ?? this.logoPath,
      encabezadoPdf: encabezadoPdf,
      piePdf: piePdf,
      colorPdf: colorPdf,
      pdfBlancoNegro: pdfBlancoNegro,
      papelPdf: papelPdf,
      margenPdfMm: margenPdfMm,
      firmaPath: firmaPath,
      selloPath: selloPath,
      mostrarFirma: mostrarFirma,
      mostrarSello: mostrarSello,
      mostrarEstadoPago: mostrarEstadoPago,
      leyendaLegal: leyendaLegal,
      diasVencimiento: diasVencimiento,
    );
  }
}
