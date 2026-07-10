import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'branding_service.dart';

class PdfService {
  String _formatearFecha(String? fechaTexto) {
    final fecha = DateTime.tryParse(fechaTexto ?? '') ?? DateTime.now();
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  double _resolverPrecio(Map<String, dynamic> item) {
    final precio = item['precioUnitario'] ?? item['precio'];
    return (precio as num?)?.toDouble() ?? 0;
  }

  Uint8List _bytesVacios() => Uint8List(0);

  Future<Uint8List> generateRemitoPdf(
    Map<String, dynamic> remito,
    List items,
    String clienteNombre, {
    String? clienteDireccion,
    String? clienteTelefono,
  }) async {
    if (items.isEmpty) return _bytesVacios();

    final branding = BrandingService.instance;
    final pdf = pw.Document();

    // Load logo if available
    pw.ImageProvider? logoImage;
    if (branding.logoPath.isNotEmpty) {
      try {
        final bytes = await File(branding.logoPath).readAsBytes();
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    final total = (remito['total'] as num?)?.toDouble() ?? 0;
    final descuento = (remito['descuento'] as num?)?.toDouble() ?? 0;
    final estadoPago = remito['estadoPago']?.toString() ?? 'pendiente';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          // ── Header ──────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (logoImage != null) ...[
                      pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(logoImage, width: 50, height: 50),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          branding.nombre,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        if (branding.slogan.isNotEmpty)
                          pw.Text(
                            branding.slogan,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.white,
                            ),
                          ),
                        if (branding.telefono.isNotEmpty)
                          pw.Text(
                            branding.telefono,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.white,
                            ),
                          ),
                        if (branding.direccion.isNotEmpty)
                          pw.Text(
                            branding.direccion,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.white,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'REMITO',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      remito['numero']?.toString() ?? '',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Fecha: ${_formatearFecha(remito['fecha']?.toString())}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // ── Cliente ──────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CLIENTE',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  clienteNombre.isEmpty ? 'Sin cliente' : clienteNombre,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (clienteDireccion != null && clienteDireccion.isNotEmpty)
                  pw.Text(clienteDireccion,
                      style: const pw.TextStyle(fontSize: 10)),
                if (clienteTelefono != null && clienteTelefono.isNotEmpty)
                  pw.Text(clienteTelefono,
                      style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // ── Tabla de productos ────────────────────────
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: pw.BoxDecoration(
              color: PdfColors.orange,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            headers: const ['Producto', 'Cant.', 'P. Unit.', 'Subtotal'],
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            data: items.map<List<String>>((item) {
              final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0;
              return [
                item['descripcion']?.toString() ?? '',
                '${item['cantidad'] ?? 0}',
                '\$${_resolverPrecio(item).toStringAsFixed(2)}',
                '\$${subtotal.toStringAsFixed(2)}',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 16),
          // ── Totales ──────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: [
                  if (descuento > 0) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Subtotal:',
                          style: pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          '\$${(total / (1 - descuento / 100)).toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Descuento ${descuento.toStringAsFixed(0)}%:',
                            style: pw.TextStyle(
                                fontSize: 10, color: PdfColors.green)),
                        pw.Text(
                          '-\$${(total / (1 - descuento / 100) * descuento / 100).toStringAsFixed(2)}',
                          style: pw.TextStyle(
                              fontSize: 10, color: PdfColors.green),
                        ),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey300),
                  ],
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL:',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange,
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
                ),
              pw.SizedBox(width: 8),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: estadoPago == 'cobrado'
                      ? PdfColors.green100
                      : estadoPago == 'parcial'
                          ? PdfColors.blue100
                          : PdfColors.orange100,
                  borderRadius: pw.BorderRadius.circular(20),
                  border: pw.Border.all(
                    color: estadoPago == 'cobrado'
                        ? PdfColors.green
                        : estadoPago == 'parcial'
                            ? PdfColors.blue
                            : PdfColors.orange,
                  ),
                ),
                child: pw.Text(
                  estadoPago.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: estadoPago == 'cobrado'
                        ? PdfColors.green900
                        : estadoPago == 'parcial'
                            ? PdfColors.blue900
                            : PdfColors.orange900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
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
              color: PdfColors.orange,
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
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: pw.BoxDecoration(
              color: PdfColors.orange,
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
