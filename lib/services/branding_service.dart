import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _keyPapelPdf = 'brandPapelPdf';
  static const _keyMargenPdf = 'brandMargenPdf';
  static const _keyFirma = 'brandFirmaPath';
  static const _keySello = 'brandSelloPath';
  static const _keyMostrarFirma = 'brandMostrarFirma';
  static const _keyMostrarSello = 'brandMostrarSello';
  static const _keyMostrarEstadoPago = 'brandMostrarEstadoPago';
  static const _keyLeyendaLegal = 'brandLeyendaLegal';

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
  /// Hex sin #, ej. FF7A00
  String colorPdf = 'FF7A00';
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

  /// Imagen preferida para UI: icono si existe, si no logo.
  String get imagenUiPath =>
      iconoPath.isNotEmpty ? iconoPath : logoPath;

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
    colorPdf = prefs.getString(_keyColorPdf) ?? 'FF7A00';
    papelPdf = prefs.getString(_keyPapelPdf) ?? 'a4';
    margenPdfMm = prefs.getDouble(_keyMargenPdf) ?? 10;
    firmaPath = prefs.getString(_keyFirma) ?? '';
    selloPath = prefs.getString(_keySello) ?? '';
    mostrarFirma = prefs.getBool(_keyMostrarFirma) ?? true;
    mostrarSello = prefs.getBool(_keyMostrarSello) ?? true;
    mostrarEstadoPago = prefs.getBool(_keyMostrarEstadoPago) ?? true;
    leyendaLegal = prefs.getString(_keyLeyendaLegal) ?? '';
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
    String? papelPdf,
    double? margenPdfMm,
    String? firmaPath,
    String? selloPath,
    bool? mostrarFirma,
    bool? mostrarSello,
    bool? mostrarEstadoPago,
    String? leyendaLegal,
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
    await prefs.setString(_keyColorPdf, colorPdf ?? this.colorPdf);
    await prefs.setString(_keyPapelPdf, papelPdf ?? this.papelPdf);
    await prefs.setDouble(_keyMargenPdf, margenPdfMm ?? this.margenPdfMm);
    await prefs.setString(_keyFirma, firmaPath ?? this.firmaPath);
    await prefs.setString(_keySello, selloPath ?? this.selloPath);
    await prefs.setBool(_keyMostrarFirma, mostrarFirma ?? this.mostrarFirma);
    await prefs.setBool(_keyMostrarSello, mostrarSello ?? this.mostrarSello);
    await prefs.setBool(
        _keyMostrarEstadoPago, mostrarEstadoPago ?? this.mostrarEstadoPago);
    await prefs.setString(_keyLeyendaLegal, leyendaLegal ?? this.leyendaLegal);

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
    if (colorPdf != null) this.colorPdf = colorPdf;
    if (papelPdf != null) this.papelPdf = papelPdf;
    if (margenPdfMm != null) this.margenPdfMm = margenPdfMm;
    if (firmaPath != null) this.firmaPath = firmaPath;
    if (selloPath != null) this.selloPath = selloPath;
    if (mostrarFirma != null) this.mostrarFirma = mostrarFirma;
    if (mostrarSello != null) this.mostrarSello = mostrarSello;
    if (mostrarEstadoPago != null) this.mostrarEstadoPago = mostrarEstadoPago;
    if (leyendaLegal != null) this.leyendaLegal = leyendaLegal;
    notifyListeners();
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
    String? logoPath,
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
      papelPdf: papelPdf,
      margenPdfMm: margenPdfMm,
      firmaPath: firmaPath,
      selloPath: selloPath,
      mostrarFirma: mostrarFirma,
      mostrarSello: mostrarSello,
      mostrarEstadoPago: mostrarEstadoPago,
      leyendaLegal: leyendaLegal,
    );
  }
}
