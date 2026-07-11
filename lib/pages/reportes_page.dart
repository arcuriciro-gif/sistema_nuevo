import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/cliente_service.dart';
import '../services/compra_service.dart';
import '../services/csv_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/excel_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../services/proveedor_service.dart';
import '../services/remito_service.dart';
import '../theme/module_app_bar.dart';
import '../models/pago.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  final ProductoService productoService = ProductoService();
  final ClienteService clienteService = ClienteService();
  final ProveedorService proveedorService = ProveedorService();
  final RemitoService remitoService = RemitoService();
  final CompraService compraService = CompraService();
  final CuentaCorrienteService ccService = CuentaCorrienteService();
  final PdfService pdfService = PdfService();
  final CsvService csvService = CsvService();
  final ExcelService excelService = ExcelService();

  bool generando = false;

  bool get _esEscritorio =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  String _mimeDeArchivo(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.csv':
        return 'text/csv';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _abrirArchivo(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path], runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {
      // Si el SO no puede abrir el archivo, el SnackBar ya muestra la ruta.
    }
  }

  /// En escritorio (Windows/EXE) el share de archivos suele fallar en silencio.
  /// Preferimos "Guardar como…" + feedback con la ruta.
  Future<void> _entregarArchivo(String path, {required String titulo}) async {
    final nombre = p.basename(path);
    final mime = _mimeDeArchivo(path);
    final origen = File(path);
    final bytes = await origen.readAsBytes();
    final ext = p.extension(nombre).replaceFirst('.', '');

    if (_esEscritorio) {
      final destino = await FilePicker.saveFile(
        dialogTitle: 'Guardar reporte — $titulo',
        fileName: nombre,
        type: FileType.custom,
        allowedExtensions: ext.isEmpty ? null : [ext],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (destino == null) return;

      final out = File(destino);
      if (!await out.exists() || await out.length() == 0) {
        await out.writeAsBytes(bytes, flush: true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reporte guardado:\n$destino'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => _abrirArchivo(destino),
          ),
        ),
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mime, name: nombre)],
        text: titulo,
        subject: titulo,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Reporte listo: $nombre')));
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() => generando = true);
    try {
      await accion();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar el reporte: $e')),
      );
    } finally {
      if (mounted) setState(() => generando = false);
    }
  }

  Future<void> _exportarListaPdf({
    required String titulo,
    required String archivo,
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() cargarFilas,
  }) => _ejecutar(() async {
    final filas = await cargarFilas();
    final pdf = await pdfService.generateListPdf(
      titulo: titulo,
      headers: headers,
      filas: filas
          .map((fila) => fila.map((valor) => valor?.toString() ?? '').toList())
          .toList(),
    );
    final file = await pdfService.guardarPdfReporte(pdf, archivo);
    await _entregarArchivo(file.path, titulo: titulo);
  });

  Future<void> _exportarListaCsv({
    required String titulo,
    required String archivo,
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() cargarFilas,
  }) => _ejecutar(() async {
    final filas = await cargarFilas();
    final file = await csvService.exportarCsv(archivo, headers, filas);
    await _entregarArchivo(file.path, titulo: titulo);
  });

  Future<void> _exportarListaExcel({
    required String titulo,
    required String hoja,
    required String archivo,
    required List<String> headers,
    required Future<List<List<dynamic>>> Function() cargarFilas,
  }) => _ejecutar(() async {
    final filas = await cargarFilas();
    final file = await excelService.exportarLibro(
      nombreHoja: hoja,
      nombreArchivo: archivo,
      headers: headers,
      filas: filas,
    );
    await _entregarArchivo(file.path, titulo: titulo);
  });

  Future<List<List<dynamic>>> _filasProductos() async {
    final productos = await productoService.obtenerTodos();
    return productos
        .map(
          (p) => [
            p.codigo,
            p.descripcion,
            p.marca,
            p.categoria,
            p.stock,
            p.costo,
            p.precio,
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasClientes() async {
    final clientes = await clienteService.obtenerTodos();
    return clientes
        .map(
          (c) => [
            c.nombreCompleto,
            c.telefono,
            c.email,
            c.direccion,
            c.localidad,
            c.saldo,
          ],
        )
        .toList();
  }

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/'
      '${f.year}';

  Future<List<List<dynamic>>> _filasDeudores() async {
    final deudores = await ccService.clientesDeudores();
    return deudores
        .map(
          (d) => [
            d.nombre,
            d.telefono,
            d.saldoPendiente,
            d.ventasPendientes,
            d.ultimaCompra == null ? '-' : _fmtFecha(d.ultimaCompra!),
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasCuentasCobrar() async {
    final ventas = await ccService.ventasConSaldo();
    return ventas
        .map(
          (v) => [
            v.clienteNombre ?? 'Sin cliente',
            v.numero,
            _fmtFecha(v.fecha),
            v.total,
            v.totalPagado,
            v.saldoPendiente,
            v.estadoPagoLabel,
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasCobros(
    DateTime desde,
    DateTime hasta,
  ) async {
    final pagos = await ccService.pagosPorPeriodo(desde, hasta);
    return pagos
        .map(
          (p) => [
            _fmtFecha(p.fecha),
            p.clienteNombre ?? '-',
            p.ventaNumero ?? p.ventaId,
            p.monto,
            Pago.labelMedio(p.medioPago),
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasCobrosDia() async {
    final ahora = DateTime.now();
    final desde = DateTime(ahora.year, ahora.month, ahora.day);
    return _filasCobros(desde, ahora);
  }

  Future<List<List<dynamic>>> _filasCobrosMes() async {
    final ahora = DateTime.now();
    final desde = DateTime(ahora.year, ahora.month, 1);
    return _filasCobros(desde, ahora);
  }

  Future<List<List<dynamic>>> _filasDeudaTotal() async {
    final resumen = await ccService.resumenDashboard();
    return [
      ['Deuda total', resumen.montoTotalPendiente],
      ['Clientes con deuda', resumen.clientesConDeuda],
      ['Ventas pendientes', resumen.ventasPendientes],
      [
        'Mayor deudor',
        resumen.mayorDeudor == null
            ? '-'
            : '${resumen.mayorDeudor!.nombre} (\$${resumen.mayorDeudor!.saldoPendiente.toStringAsFixed(2)})',
      ],
    ];
  }

  Future<List<List<dynamic>>> _filasProveedores() async {
    final proveedores = await proveedorService.obtenerTodos();
    return proveedores
        .map(
          (p) => [
            p.nombre,
            p.contacto,
            p.telefono,
            p.email,
            p.condicionesComerciales,
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasRemitos() async {
    final remitos = await remitoService.obtenerTodosConCliente();
    return remitos
        .map(
          (r) => [
            r['numero'] ?? '',
            r['clienteNombre'] ?? 'Sin cliente',
            r['fecha'] ?? '',
            r['estado'] ?? '',
            r['estadoPago'] ?? '',
            (r['total'] as num?)?.toDouble() ?? 0,
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasCompras() async {
    final compras = await compraService.obtenerTodasConProveedor();
    return compras
        .map(
          (c) => [
            c['numero'] ?? '',
            c['factura'] ?? '',
            c['proveedorNombre'] ?? 'Sin proveedor',
            c['fecha'] ?? '',
            c['estado'] ?? '',
            (c['total'] as num?)?.toDouble() ?? 0,
          ],
        )
        .toList();
  }

  Future<List<List<dynamic>>> _filasInventario() async {
    final productos = await productoService.obtenerTodos();
    return productos
        .map(
          (p) => [p.codigo, p.descripcion, p.stock, p.costo, p.costo * p.stock],
        )
        .toList();
  }

  Widget _tarjetaReporte({
    required IconData icon,
    required String titulo,
    required String descripcion,
    required VoidCallback onPdf,
    required VoidCallback onCsv,
    required VoidCallback onExcel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(icon, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        descripcion,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: generando ? null : onPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: generando ? null : onCsv,
                    icon: const Icon(Icons.table_chart_rounded, size: 18),
                    label: const Text('CSV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: generando ? null : onExcel,
                    icon: const Icon(Icons.grid_on_rounded, size: 18),
                    label: const Text('Excel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Reportes'),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Reportes',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Generá reportes en PDF, CSV o Excel. En Windows se abre Guardar como…; en el celular, compartir.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _tarjetaReporte(
                icon: Icons.inventory_2_rounded,
                titulo: 'Lista de productos',
                descripcion: 'Código, descripción, marca, stock y precios',
                onPdf: () => _exportarListaPdf(
                  titulo: 'LISTA DE PRODUCTOS',
                  archivo: 'productos.pdf',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Marca',
                    'Categoría',
                    'Stock',
                    'Costo',
                    'Precio',
                  ],
                  cargarFilas: _filasProductos,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'LISTA DE PRODUCTOS',
                  archivo: 'productos.csv',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Marca',
                    'Categoría',
                    'Stock',
                    'Costo',
                    'Precio',
                  ],
                  cargarFilas: _filasProductos,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'LISTA DE PRODUCTOS',
                  hoja: 'Productos',
                  archivo: 'productos.xlsx',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Marca',
                    'Categoría',
                    'Stock',
                    'Costo',
                    'Precio',
                  ],
                  cargarFilas: _filasProductos,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.groups_rounded,
                titulo: 'Lista de clientes',
                descripcion: 'Datos de contacto y saldo',
                onPdf: () => _exportarListaPdf(
                  titulo: 'LISTA DE CLIENTES',
                  archivo: 'clientes.pdf',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Email',
                    'Dirección',
                    'Localidad',
                    'Saldo',
                  ],
                  cargarFilas: _filasClientes,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'LISTA DE CLIENTES',
                  archivo: 'clientes.csv',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Email',
                    'Dirección',
                    'Localidad',
                    'Saldo',
                  ],
                  cargarFilas: _filasClientes,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'LISTA DE CLIENTES',
                  hoja: 'Clientes',
                  archivo: 'clientes.xlsx',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Email',
                    'Dirección',
                    'Localidad',
                    'Saldo',
                  ],
                  cargarFilas: _filasClientes,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.account_balance_wallet_rounded,
                titulo: 'Clientes deudores',
                descripcion: 'Clientes con saldo pendiente',
                onPdf: () => _exportarListaPdf(
                  titulo: 'CLIENTES DEUDORES',
                  archivo: 'clientes_deudores.pdf',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Saldo',
                    'Ventas pend.',
                    'Última compra',
                  ],
                  cargarFilas: _filasDeudores,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'CLIENTES DEUDORES',
                  archivo: 'clientes_deudores.csv',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Saldo',
                    'Ventas pend.',
                    'Última compra',
                  ],
                  cargarFilas: _filasDeudores,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'CLIENTES DEUDORES',
                  hoja: 'Deudores',
                  archivo: 'clientes_deudores.xlsx',
                  headers: const [
                    'Nombre',
                    'Teléfono',
                    'Saldo',
                    'Ventas pend.',
                    'Última compra',
                  ],
                  cargarFilas: _filasDeudores,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.request_quote_rounded,
                titulo: 'Cuentas por cobrar',
                descripcion: 'Ventas con saldo pendiente',
                onPdf: () => _exportarListaPdf(
                  titulo: 'CUENTAS POR COBRAR',
                  archivo: 'cuentas_por_cobrar.pdf',
                  headers: const [
                    'Cliente',
                    'Comprobante',
                    'Fecha',
                    'Total',
                    'Pagado',
                    'Saldo',
                    'Estado',
                  ],
                  cargarFilas: _filasCuentasCobrar,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'CUENTAS POR COBRAR',
                  archivo: 'cuentas_por_cobrar.csv',
                  headers: const [
                    'Cliente',
                    'Comprobante',
                    'Fecha',
                    'Total',
                    'Pagado',
                    'Saldo',
                    'Estado',
                  ],
                  cargarFilas: _filasCuentasCobrar,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'CUENTAS POR COBRAR',
                  hoja: 'Cuentas',
                  archivo: 'cuentas_por_cobrar.xlsx',
                  headers: const [
                    'Cliente',
                    'Comprobante',
                    'Fecha',
                    'Total',
                    'Pagado',
                    'Saldo',
                    'Estado',
                  ],
                  cargarFilas: _filasCuentasCobrar,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.payments_rounded,
                titulo: 'Cobros del día',
                descripcion: 'Pagos registrados hoy',
                onPdf: () => _exportarListaPdf(
                  titulo: 'COBROS DEL DÍA',
                  archivo: 'cobros_dia.pdf',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosDia,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'COBROS DEL DÍA',
                  archivo: 'cobros_dia.csv',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosDia,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'COBROS DEL DÍA',
                  hoja: 'CobrosDia',
                  archivo: 'cobros_dia.xlsx',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosDia,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.calendar_month_rounded,
                titulo: 'Cobros del mes',
                descripcion: 'Pagos del mes en curso',
                onPdf: () => _exportarListaPdf(
                  titulo: 'COBROS DEL MES',
                  archivo: 'cobros_mes.pdf',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosMes,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'COBROS DEL MES',
                  archivo: 'cobros_mes.csv',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosMes,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'COBROS DEL MES',
                  hoja: 'CobrosMes',
                  archivo: 'cobros_mes.xlsx',
                  headers: const [
                    'Fecha',
                    'Cliente',
                    'Comprobante',
                    'Monto',
                    'Medio',
                  ],
                  cargarFilas: _filasCobrosMes,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.summarize_rounded,
                titulo: 'Deuda total',
                descripcion: 'Resumen de deuda acumulada',
                onPdf: () => _exportarListaPdf(
                  titulo: 'DEUDA TOTAL',
                  archivo: 'deuda_total.pdf',
                  headers: const ['Concepto', 'Valor'],
                  cargarFilas: _filasDeudaTotal,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'DEUDA TOTAL',
                  archivo: 'deuda_total.csv',
                  headers: const ['Concepto', 'Valor'],
                  cargarFilas: _filasDeudaTotal,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'DEUDA TOTAL',
                  hoja: 'Deuda',
                  archivo: 'deuda_total.xlsx',
                  headers: const ['Concepto', 'Valor'],
                  cargarFilas: _filasDeudaTotal,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.local_shipping_rounded,
                titulo: 'Lista de proveedores',
                descripcion: 'Datos de contacto y condiciones comerciales',
                onPdf: () => _exportarListaPdf(
                  titulo: 'LISTA DE PROVEEDORES',
                  archivo: 'proveedores.pdf',
                  headers: const [
                    'Nombre',
                    'Contacto',
                    'Teléfono',
                    'Email',
                    'Condiciones',
                  ],
                  cargarFilas: _filasProveedores,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'LISTA DE PROVEEDORES',
                  archivo: 'proveedores.csv',
                  headers: const [
                    'Nombre',
                    'Contacto',
                    'Teléfono',
                    'Email',
                    'Condiciones',
                  ],
                  cargarFilas: _filasProveedores,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'LISTA DE PROVEEDORES',
                  hoja: 'Proveedores',
                  archivo: 'proveedores.xlsx',
                  headers: const [
                    'Nombre',
                    'Contacto',
                    'Teléfono',
                    'Email',
                    'Condiciones',
                  ],
                  cargarFilas: _filasProveedores,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.description_rounded,
                titulo: 'Resumen de remitos',
                descripcion: 'Cliente, fecha, estado y total facturado',
                onPdf: () => _exportarListaPdf(
                  titulo: 'LISTA DE REMITOS',
                  archivo: 'remitos.pdf',
                  headers: const [
                    'Número',
                    'Cliente',
                    'Fecha',
                    'Estado',
                    'Pago',
                    'Total',
                  ],
                  cargarFilas: _filasRemitos,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'LISTA DE REMITOS',
                  archivo: 'remitos.csv',
                  headers: const [
                    'Número',
                    'Cliente',
                    'Fecha',
                    'Estado',
                    'Pago',
                    'Total',
                  ],
                  cargarFilas: _filasRemitos,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'LISTA DE REMITOS',
                  hoja: 'Remitos',
                  archivo: 'remitos.xlsx',
                  headers: const [
                    'Número',
                    'Cliente',
                    'Fecha',
                    'Estado',
                    'Pago',
                    'Total',
                  ],
                  cargarFilas: _filasRemitos,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.shopping_cart_rounded,
                titulo: 'Resumen de compras',
                descripcion: 'Proveedor, factura, estado y total comprado',
                onPdf: () => _exportarListaPdf(
                  titulo: 'LISTA DE COMPRAS',
                  archivo: 'compras.pdf',
                  headers: const [
                    'Número',
                    'Factura',
                    'Proveedor',
                    'Fecha',
                    'Estado',
                    'Total',
                  ],
                  cargarFilas: _filasCompras,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'LISTA DE COMPRAS',
                  archivo: 'compras.csv',
                  headers: const [
                    'Número',
                    'Factura',
                    'Proveedor',
                    'Fecha',
                    'Estado',
                    'Total',
                  ],
                  cargarFilas: _filasCompras,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'LISTA DE COMPRAS',
                  hoja: 'Compras',
                  archivo: 'compras.xlsx',
                  headers: const [
                    'Número',
                    'Factura',
                    'Proveedor',
                    'Fecha',
                    'Estado',
                    'Total',
                  ],
                  cargarFilas: _filasCompras,
                ),
              ),
              _tarjetaReporte(
                icon: Icons.warehouse_rounded,
                titulo: 'Inventario con valor',
                descripcion: 'Stock valorizado a costo por producto',
                onPdf: () => _exportarListaPdf(
                  titulo: 'INVENTARIO CON VALOR',
                  archivo: 'inventario_valor.pdf',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Stock',
                    'Costo unit.',
                    'Valor total',
                  ],
                  cargarFilas: _filasInventario,
                ),
                onCsv: () => _exportarListaCsv(
                  titulo: 'INVENTARIO CON VALOR',
                  archivo: 'inventario_valor.csv',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Stock',
                    'Costo unit.',
                    'Valor total',
                  ],
                  cargarFilas: _filasInventario,
                ),
                onExcel: () => _exportarListaExcel(
                  titulo: 'INVENTARIO CON VALOR',
                  hoja: 'Inventario',
                  archivo: 'inventario_valor.xlsx',
                  headers: const [
                    'Código',
                    'Descripción',
                    'Stock',
                    'Costo unit.',
                    'Valor total',
                  ],
                  cargarFilas: _filasInventario,
                ),
              ),
            ],
          ),
          if (generando)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
