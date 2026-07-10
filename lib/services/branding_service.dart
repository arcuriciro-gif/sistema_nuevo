import 'package:shared_preferences/shared_preferences.dart';

class BrandingService {
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
  static const _keyMoneda = 'brandMoneda';
  static const _keyFormatoFecha = 'brandFormatoFecha';
  static const _keyCuit = 'brandCuit';
  static const _keyIngresosBrutos = 'brandIngresosBrutos';
  static const _keyCondicionIva = 'brandCondicionIva';
  static const _keyDireccionFiscal = 'brandDireccionFiscal';
  static const _keyEncabezadoPdf = 'brandEncabezadoPdf';
  static const _keyPiePdf = 'brandPiePdf';
  static const _keyColorPdf = 'brandColorPdf';

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
    moneda = prefs.getString(_keyMoneda) ?? r'$';
    formatoFecha = prefs.getString(_keyFormatoFecha) ?? 'dd/MM/yyyy';
    cuit = prefs.getString(_keyCuit) ?? '';
    ingresosBrutos = prefs.getString(_keyIngresosBrutos) ?? '';
    condicionIva = prefs.getString(_keyCondicionIva) ?? '';
    direccionFiscal = prefs.getString(_keyDireccionFiscal) ?? '';
    encabezadoPdf = prefs.getString(_keyEncabezadoPdf) ?? '';
    piePdf = prefs.getString(_keyPiePdf) ?? '';
    colorPdf = prefs.getString(_keyColorPdf) ?? 'FF7A00';
  }

  Future<void> guardar({
    required String nombre,
    required String slogan,
    required String telefono,
    required String direccion,
    required String logoPath,
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre);
    await prefs.setString(_keySlogan, slogan);
    await prefs.setString(_keyTelefono, telefono);
    await prefs.setString(_keyDireccion, direccion);
    await prefs.setString(_keyLogo, logoPath);
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

    this.nombre = nombre;
    this.slogan = slogan;
    this.telefono = telefono;
    this.direccion = direccion;
    this.logoPath = logoPath;
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
  }
}
