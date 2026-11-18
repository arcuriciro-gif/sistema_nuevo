import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'branding_service.dart';

class PdfService {
  String _formatearFecha(String? fechaTexto) {
    final branding = BrandingService.instance;
    final fecha = DateTime.tryParse(fechaTexto ?? '') ?? DateTime.now();
    final dd = fecha.day.toString().padLeft(2, '0');
    final mm = fecha.month.toString().padLeft(2, '0');
    final yyyy = '${fecha.year}';
    switch (branding.formatoFecha) {
      case 'MM/dd/yyyy':
        return '$mm/$dd/$yyyy';
      case 'yyyy-MM-dd':
        return '$yyyy-$mm-$dd';
      default:
        return '$dd/$mm/$yyyy';
    }
  }

  String _monto(num value) {
    final moneda = BrandingService.instance.moneda;
    return '$moneda${value.toStringAsFixed(2)}';
  }

  PdfColor? _colorMarcaONull() {
    final branding = BrandingService.instance;
    if (branding.encabezadoPdfTransparente) return null;
    final raw = BrandingService.normalizarColorPdf(branding.colorPdf);
    if (raw == BrandingService.colorPdfTransparente) return null;
    try {
      return PdfColor.fromInt(int.parse('FF$raw', radix: 16));
    } catch (_) {
      return PdfColors.orange;
    }
  }

  PdfColor _colorMarca() => _colorMarcaONull() ?? PdfColors.grey800;

  PdfColor _colorTextoSobreMarca() {
    return BrandingService.instance.encabezadoPdfTransparente
        ? PdfColors.black
        : PdfColors.white;
  }

  PdfColor _colorAcentoTabla() {
    if (BrandingService.instance.pdfBlancoNegro ||
        BrandingService.instance.encabezadoPdfTransparente) {
      return PdfColors.grey800;
    }
    return _colorMarca();
  }

  double _resolverPrecio(Map<String, dynamic> item) {
    final precio = item['precioUnitario'] ?? item['precio'];
    return (precio as num?)?.toDouble() ?? 0;
  }

  Uint8List _bytesVacios() => Uint8List(0);

  List<String> _lineasContacto(BrandingService branding) {
    return [
      if (branding.telefono.isNotEmpty) 'Tel: ${branding.telefono}',
      if (branding.whatsapp.isNotEmpty) 'WhatsApp: ${branding.whatsapp}',
      if (branding.email.isNotEmpty) branding.email,
      if (branding.sitioWeb.isNotEmpty) branding.sitioWeb,
      if (branding.instagram.isNotEmpty) 'IG: ${branding.instagram}',
      if (branding.facebook.isNotEmpty) 'FB: ${branding.facebook}',
    ];
  }

  List<String> _lineasFiscales(BrandingService branding) {
    return [
      if (branding.cuit.isNotEmpty) 'CUIT: ${branding.cuit}',
      if (branding.ingresosBrutos.isNotEmpty) 'IIBB: ${branding.ingresosBrutos}',
      if (branding.condicionIva.isNotEmpty) branding.condicionIva,
      if (branding.direccionFiscal.isNotEmpty) branding.direccionFiscal,
    ];
  }

  PdfPageFormat _pageFormat(BrandingService branding) {
    switch (branding.papelPdf) {
      case 'ticket_80':
        return PdfPageFormat.roll80;
      case 'ticket_58':
        return PdfPageFormat.roll57;
      default:
        return PdfPageFormat.a4;
    }
  }

  pw.EdgeInsets _pageMargin(BrandingService branding) {
    final mm = branding.margenPdfMm.clamp(2, 30);
    final pts = mm * PdfPageFormat.mm;
    return pw.EdgeInsets.all(pts);
  }

  Future<pw.ImageProvider?> _cargarImagen(String path) async {
    if (path.isEmpty) return null;
    try {
      final bytes = await File(path).readAsBytes();
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> generateRemitoPdf(
    Map<String, dynamic> remito,
    List items,
    String clienteNombre, {
    String? clienteDireccion,
    String? clienteTelefono,
    String tipoDocumento = 'REMITO',
  }) async {
    if (items.isEmpty) return _bytesVacios();

    final branding = BrandingService.instance;
    final pdf = pw.Document();

    final logoImage = await _cargarImagen(branding.logoPath);
    final firmaImage = branding.mostrarFirma
        ? await _cargarImagen(branding.firmaPath)
        : null;
    final selloImage = branding.mostrarSello
        ? await _cargarImagen(branding.selloPath)
        : null;

    final total = (remito['total'] as num?)?.toDouble() ?? 0;
    final descuento = (remito['descuento'] as num?)?.toDouble() ?? 0;
    final estadoPago = remito['estadoPago']?.toString() ?? 'pendiente';
    final colorMarca = _colorMarcaONull();
    final colorTexto = _colorTextoSobreMarca();
    final transparente = branding.encabezadoPdfTransparente;
    final contacto = _lineasContacto(branding);
    final fiscales = _lineasFiscales(branding);
    final esTicket = branding.papelPdf.startsWith('ticket');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat(branding),
        margin: _pageMargin(branding),
        build: (context) => [
          if (branding.encabezadoPdf.isNotEmpty) ...[
            pw.Text(
              branding.encabezadoPdf,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
          // ── Header ──────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: colorMarca,
              border: transparente
                  ? pw.Border.all(color: PdfColors.grey400, width: 0.8)
                  : null,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null) ...[
                  pw.ClipRRect(
                    horizontalRadius: 4,
                    verticalRadius: 4,
                    child: pw.Image(logoImage, width: esTicket ? 36 : 48, height: esTicket ? 36 : 48),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        branding.nombre,
                        style: pw.TextStyle(
                          fontSize: esTicket ? 14 : 18,
                          fontWeight: pw.FontWeight.bold,
                          color: colorTexto,
                        ),
                      ),
                      if (branding.slogan.isNotEmpty)
                        pw.Text(
                          branding.slogan,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: colorTexto,
                          ),
                        ),
                      if (branding.direccion.isNotEmpty)
                        pw.Text(
                          branding.direccion,
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: colorTexto,
                          ),
                        ),
                      if (fiscales.isNotEmpty)
                        pw.Text(
                          fiscales.join(' · '),
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: colorTexto,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      tipoDocumento,
                      style: pw.TextStyle(
                        fontSize: esTicket ? 10 : 12,
                        fontWeight: pw.FontWeight.bold,
                        color: colorTexto,
                      ),
                    ),
                    pw.Text(
                      remito['numero']?.toString() ?? '',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: colorTexto,
                      ),
                    ),
                    pw.Text(
                      _formatearFecha(remito['fecha']?.toString()),
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: colorTexto,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // ── Cliente ─────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cliente: $clienteNombre',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if ((clienteDireccion ?? '').isNotEmpty)
                  pw.Text(
                    clienteDireccion!,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if ((clienteTelefono ?? '').isNotEmpty)
                  pw.Text(
                    'Tel: $clienteTelefono',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // ── Items table ─────────────────────────────
          pw.TableHelper.fromTextArray(
            headers: esTicket
                ? ['Desc.', 'Cant', 'Total']
                : ['Descripción', 'Cant.', 'P. Unit.', 'Subtotal'],
            data: items.map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              final cant = (item['cantidad'] as num?)?.toDouble() ?? 0;
              final precio = _resolverPrecio(item);
              final sub = (item['subtotal'] as num?)?.toDouble() ??
                  (cant * precio);
              if (esTicket) {
                return [
                  item['descripcion']?.toString() ?? '',
                  cant.toStringAsFixed(cant % 1 == 0 ? 0 : 2),
                  _monto(sub),
                ];
              }
              return [
                item['descripcion']?.toString() ?? '',
                cant.toStringAsFixed(cant % 1 == 0 ? 0 : 2),
                _monto(precio),
                _monto(sub),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: esTicket ? 8 : 10,
            ),
            headerDecoration: pw.BoxDecoration(color: _colorAcentoTabla()),
            cellStyle: pw.TextStyle(fontSize: esTicket ? 8 : 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: esTicket
                ? {
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerRight,
                  }
                : {
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                  },
          ),
          pw.SizedBox(height: 12),
          // ── Totales ─────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: esTicket ? double.infinity : 220,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                children: [
                  if (descuento > 0)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Descuento',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('-${_monto(descuento)}',
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _monto(total),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          // ── Estado de pago ────────────────────────────
          if (branding.mostrarEstadoPago)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if ((remito['observaciones'] as String? ?? '').isNotEmpty)
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Observaciones:',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey600)),
                          pw.Text(
                            remito['observaciones']?.toString() ?? '',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  )
                else if ((remito['observaciones'] as String? ?? '').isEmpty)
                  pw.SizedBox(),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: branding.pdfBlancoNegro
                        ? PdfColors.grey200
                        : estadoPago == 'cobrado'
                            ? PdfColors.green100
                            : estadoPago == 'parcial'
                                ? PdfColors.blue100
                                : PdfColors.orange100,
                    borderRadius: pw.BorderRadius.circular(20),
                    border: pw.Border.all(
                      color: branding.pdfBlancoNegro
                          ? PdfColors.grey700
                          : estadoPago == 'cobrado'
                              ? PdfColors.green
                              : estadoPago == 'parcial'
                                  ? PdfColors.blue
                                  : _colorAcentoTabla(),
                    ),
                  ),
                  child: pw.Text(
                    estadoPago.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: branding.pdfBlancoNegro
                          ? PdfColors.black
                          : estadoPago == 'cobrado'
                              ? PdfColors.green900
                              : estadoPago == 'parcial'
                                  ? PdfColors.blue900
                                  : PdfColors.orange900,
                    ),
                  ),
                ),
              ],
            )
          else if ((remito['observaciones'] as String? ?? '').isNotEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Observaciones:',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey600)),
                  pw.Text(
                    remito['observaciones']?.toString() ?? '',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          if (firmaImage != null || selloImage != null) ...[
            pw.SizedBox(height: 28),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                if (firmaImage != null)
                  pw.Column(
                    children: [
                      pw.Image(firmaImage, height: 48),
                      pw.SizedBox(height: 4),
                      pw.Text('Firma',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                if (selloImage != null)
                  pw.Column(
                    children: [
                      pw.Image(selloImage, height: 48),
                      pw.SizedBox(height: 4),
                      pw.Text('Sello',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
              ],
            ),
          ],
          if (branding.piePdf.isNotEmpty ||
              branding.leyendaLegal.isNotEmpty ||
              contacto.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),
            if (branding.piePdf.isNotEmpty)
              pw.Text(
                branding.piePdf,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            if (branding.leyendaLegal.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                branding.leyendaLegal,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
            if (contacto.isNotEmpty)
              pw.Text(
                contacto.join('  ·  '),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateFacturaPdf(
    Map<String, dynamic> venta,
    List items,
    String clienteNombre, {
    String? clienteDireccion,
    String? clienteTelefono,
    String tipoDocumento = 'FACTURA',
  }) {
    return generateRemitoPdf(
      venta,
      items,
      clienteNombre,
      clienteDireccion: clienteDireccion,
      clienteTelefono: clienteTelefono,
      tipoDocumento: tipoDocumento,
    );
  }

  Future<Uint8List> generatePresupuestoPdf(
    Map<String, dynamic> doc,
    List items,
    String clienteNombre, {
    String? clienteDireccion,
    String? clienteTelefono,
  }) {
    return generateRemitoPdf(
      doc,
      items,
      clienteNombre,
      clienteDireccion: clienteDireccion,
      clienteTelefono: clienteTelefono,
      tipoDocumento: 'PRESUPUESTO',
    );
  }

  Future<Uint8List> generateNotaEntregaPdf(
    Map<String, dynamic> doc,
    List items,
    String clienteNombre, {
    String? clienteDireccion,
    String? clienteTelefono,
  }) {
    return generateRemitoPdf(
      doc,
      items,
      clienteNombre,
      clienteDireccion: clienteDireccion,
      clienteTelefono: clienteTelefono,
      tipoDocumento: 'NOTA DE ENTREGA',
    );
  }

  Future<File> guardarPdf(Uint8List bytes, String nombreArchivo) async {
    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'remitos'));
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final archivo = File(p.join(carpeta.path, nombreArchivo));
    return archivo.writeAsBytes(bytes, flush: true);
  }

  /// Generates a generic tabular report PDF (used by Reportes page).
  Future<Uint8List> generateListPdf({
    required String titulo,
    required List<String> headers,
    required List<List<String>> filas,
  }) async {
    final branding = BrandingService.instance;
    final pdf = pw.Document();
    final colorMarca = _colorMarcaONull();
    final colorTexto = _colorTextoSobreMarca();
    final colorTabla = _colorAcentoTabla();
    final transparente = branding.encabezadoPdfTransparente;

    pw.ImageProvider? logoImage;
    if (branding.logoPath.isNotEmpty) {
      try {
        final bytes = await File(branding.logoPath).readAsBytes();
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: colorMarca,
              border: transparente
                  ? pw.Border.all(color: PdfColors.grey400, width: 0.8)
                  : null,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (logoImage != null) ...[
                      pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(logoImage, width: 40, height: 40),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Text(
                      branding.nombre,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: colorTexto,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: colorTexto,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: pw.BoxDecoration(
              color: colorTabla,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            headers: headers,
            data: filas,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<File> guardarPdfReporte(Uint8List bytes, String nombreArchivo) async {
    final directorio = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(directorio.path, 'reportes'));
    if (!await carpeta.exists()) {
      await carpeta.create(recursive: true);
    }

    final archivo = File(p.join(carpeta.path, nombreArchivo));
    return archivo.writeAsBytes(bytes, flush: true);
  }

  /// Generates a sheet of product labels (código, descripción, precio and a
  /// QR code with the product código) for printing.
  Future<Uint8List> generateEtiquetasPdf({
    required List<Map<String, dynamic>> productos,
    String tamano = 'medium',
  }) async {
    if (productos.isEmpty) return Uint8List(0);

    final pdf = pw.Document();

    final dimensiones = {
      'small': const PdfPoint(4 * PdfPageFormat.cm, 2 * PdfPageFormat.cm),
      'medium': const PdfPoint(5 * PdfPageFormat.cm, 3 * PdfPageFormat.cm),
      'large': const PdfPoint(7 * PdfPageFormat.cm, 4 * PdfPageFormat.cm),
    };
    final tamanoLabel = dimensiones[tamano] ?? dimensiones['medium']!;
    final columnas = tamano == 'large' ? 2 : (tamano == 'small' ? 4 : 3);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => [
          pw.GridView(
            crossAxisCount: columnas,
            childAspectRatio: tamanoLabel.x / tamanoLabel.y,
            children: productos.map((item) {
              final codigo = item['codigo']?.toString() ?? '';
              final descripcion = item['descripcion']?.toString() ?? '';
              final precio = (item['precio'] as num?)?.toDouble() ?? 0;

              return pw.Container(
                margin: const pw.EdgeInsets.all(4),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: codigo,
                      width: 40,
                      height: 40,
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            descripcion,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.Text(
                            codigo,
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.Text(
                            '\$${precio.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
