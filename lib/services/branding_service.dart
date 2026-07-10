import 'package:shared_preferences/shared_preferences.dart';

class BrandingService {
  static const _keyNombre = 'brandNombre';
  static const _keySlogan = 'brandSlogan';
  static const _keyTelefono = 'brandTelefono';
  static const _keyDireccion = 'brandDireccion';
  static const _keyLogo = 'brandLogoPath';
  static const _keyMoneda = 'brandMoneda';
  static const _keyFormatoFecha = 'brandFormatoFecha';
  static const _keyCuit = 'brandCuit';
  static const _keyCondicionIva = 'brandCondicionIva';
  static const _keyDireccionFiscal = 'brandDireccionFiscal';
  static const _keyEncabezadoPdf = 'brandEncabezadoPdf';
  static const _keyPiePdf = 'brandPiePdf';

  static final BrandingService instance = BrandingService._();
  BrandingService._();

  String nombre = 'EL TATA Manager';
  String slogan = 'Gestión de stock, ventas y más';
  String telefono = '';
  String direccion = '';
  String logoPath = '';
  String moneda = r'$';
  String formatoFecha = 'dd/MM/yyyy';
  String cuit = '';
  String condicionIva = '';
  String direccionFiscal = '';
  String encabezadoPdf = '';
  String piePdf = '';

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    nombre = prefs.getString(_keyNombre) ?? 'EL TATA Manager';
    slogan = prefs.getString(_keySlogan) ?? 'Gestión de stock, ventas y más';
    telefono = prefs.getString(_keyTelefono) ?? '';
    direccion = prefs.getString(_keyDireccion) ?? '';
    logoPath = prefs.getString(_keyLogo) ?? '';
    moneda = prefs.getString(_keyMoneda) ?? r'$';
    formatoFecha = prefs.getString(_keyFormatoFecha) ?? 'dd/MM/yyyy';
    cuit = prefs.getString(_keyCuit) ?? '';
    condicionIva = prefs.getString(_keyCondicionIva) ?? '';
    direccionFiscal = prefs.getString(_keyDireccionFiscal) ?? '';
    encabezadoPdf = prefs.getString(_keyEncabezadoPdf) ?? '';
    piePdf = prefs.getString(_keyPiePdf) ?? '';
  }

  Future<void> guardar({
    required String nombre,
    required String slogan,
    required String telefono,
    required String direccion,
    required String logoPath,
    String? moneda,
    String? formatoFecha,
    String? cuit,
    String? condicionIva,
    String? direccionFiscal,
    String? encabezadoPdf,
    String? piePdf,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNombre, nombre);
    await prefs.setString(_keySlogan, slogan);
    await prefs.setString(_keyTelefono, telefono);
    await prefs.setString(_keyDireccion, direccion);
    await prefs.setString(_keyLogo, logoPath);
    await prefs.setString(_keyMoneda, moneda ?? this.moneda);
    await prefs.setString(_keyFormatoFecha, formatoFecha ?? this.formatoFecha);
    await prefs.setString(_keyCuit, cuit ?? this.cuit);
    await prefs.setString(_keyCondicionIva, condicionIva ?? this.condicionIva);
    await prefs.setString(
        _keyDireccionFiscal, direccionFiscal ?? this.direccionFiscal);
    await prefs.setString(
        _keyEncabezadoPdf, encabezadoPdf ?? this.encabezadoPdf);
    await prefs.setString(_keyPiePdf, piePdf ?? this.piePdf);

    this.nombre = nombre;
    this.slogan = slogan;
    this.telefono = telefono;
    this.direccion = direccion;
    this.logoPath = logoPath;
    if (moneda != null) this.moneda = moneda;
    if (formatoFecha != null) this.formatoFecha = formatoFecha;
    if (cuit != null) this.cuit = cuit;
    if (condicionIva != null) this.condicionIva = condicionIva;
    if (direccionFiscal != null) this.direccionFiscal = direccionFiscal;
    if (encabezadoPdf != null) this.encabezadoPdf = encabezadoPdf;
    if (piePdf != null) this.piePdf = piePdf;
  }
}
