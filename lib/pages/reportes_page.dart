import 'package:flutter/material.dart';
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

  Future<void> _compartirArchivo(String path) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
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
    required List<List<dynamic>> filas,
  }) => _ejecutar(() async {
        final pdf = await pdfService.generateListPdf(
          titulo: titulo,
          headers: headers,
          filas: filas
              .map(
                (fila) => fila.map((valor) => valor?.toString() ?? '').toList(),
              )
              .toList(),
        );
        final file = await pdfService.guardarPdfReporte(pdf, archivo);
        await _compartirArchivo(file.path);
      });

  Future<void> _exportarListaCsv({
    required String archivo,
    required List<String> headers,
    required List<List<dynamic>> filas,
  }) => _ejecutar(() async {
        final file = await csvService.exportarCsv(archivo, headers, filas);
        await _compartirArchivo(file.path);
      });

  Future<void> _exportarListaExcel({
    required String hoja,
    required String archivo,
    required List<String> headers,
    required List<List<dynamic>> filas,
  }) => _ejecutar(() async {
        final file = await excelService.exportarLibro(
          nombreHoja: hoja,
          nombreArchivo: archivo,
          headers: headers,
          filas: filas,
        );
        await _compartirArchivo(file.path);
      });

  Future<List<List<dynamic>>> _filasProductos() async {
    final productos = await productoService.obtenerTodos();
    return productos
        .map((p) => [
              p.codigo,
              p.descripcion,
              p.marca,
              p.categoria,
              p.stock,
              p.costo,
              p.precio,
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasClientes() async {
    final clientes = await clienteService.obtenerTodos();
    return clientes
        .map((c) => [
              c.nombreCompleto,
              c.telefono,
              c.email,
              c.direccion,
              c.localidad,
              c.saldo,
            ])
        .toList();
  }

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/'
      '${f.year}';

  Future<List<List<dynamic>>> _filasDeudores() async {
    final deudores = await ccService.clientesDeudores();
    return deudores
        .map((d) => [
              d.nombre,
              d.telefono,
              d.saldoPendiente,
              d.ventasPendientes,
              d.ultimaCompra == null ? '-' : _fmtFecha(d.ultimaCompra!),
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasCuentasCobrar() async {
    final ventas = await ccService.ventasConSaldo();
    return ventas
        .map((v) => [
              v.clienteNombre ?? 'Sin cliente',
              v.numero,
              _fmtFecha(v.fecha),
              v.total,
              v.totalPagado,
              v.saldoPendiente,
              v.estadoPagoLabel,
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasCobros(DateTime desde, DateTime hasta) async {
    final pagos = await ccService.pagosPorPeriodo(desde, hasta);
    return pagos
        .map((p) => [
              _fmtFecha(p.fecha),
              p.clienteNombre ?? '-',
              p.ventaNumero ?? p.ventaId,
              p.monto,
              Pago.labelMedio(p.medioPago),
            ])
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
        .map((p) => [
              p.nombre,
              p.contacto,
              p.telefono,
              p.email,
              p.condicionesComerciales,
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasRemitos() async {
    final remitos = await remitoService.obtenerTodosConCliente();
    return remitos
        .map((r) => [
              r['numero'] ?? '',
              r['clienteNombre'] ?? 'Sin cliente',
              r['fecha'] ?? '',
              r['estado'] ?? '',
              r['estadoPago'] ?? '',
              (r['total'] as num?)?.toDouble() ?? 0,
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasCompras() async {
    final compras = await compraService.obtenerTodasConProveedor();
    return compras
        .map((c) => [
              c['numero'] ?? '',
              c['factura'] ?? '',
              c['proveedorNombre'] ?? 'Sin proveedor',
              c['fecha'] ?? '',
              c['estado'] ?? '',
              (c['total'] as num?)?.toDouble() ?? 0,
            ])
        .toList();
  }

  Future<List<List<dynamic>>> _filasInventario() async {
    final productos = await productoService.obtenerTodos();
    return productos
        .map((p) => [p.codigo, p.descripcion, p.stock, p.costo, p.costo * p.stock])
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
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Generá y compartí reportes en PDF, CSV o Excel.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _tarjetaReporte(
                icon: Icons.inventory_2_rounded,
                titulo: 'Lista de productos',
                descripcion: 'Código, descripción, marca, stock y precios',
                onPdf: () async {
                  final filas = await _filasProductos();
                  await _exportarListaPdf(
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
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasProductos();
                  await _exportarListaCsv(
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
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasProductos();
                  await _exportarListaExcel(
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
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.groups_rounded,
                titulo: 'Lista de clientes',
                descripcion: 'Datos de contacto y saldo',
                onPdf: () async {
                  final filas = await _filasClientes();
                  await _exportarListaPdf(
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
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasClientes();
                  await _exportarListaCsv(
                    archivo: 'clientes.csv',
                    headers: const [
                      'Nombre',
                      'Teléfono',
                      'Email',
                      'Dirección',
                      'Localidad',
                      'Saldo',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasClientes();
                  await _exportarListaExcel(
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
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.account_balance_wallet_rounded,
                titulo: 'Clientes deudores',
                descripcion: 'Clientes con saldo pendiente',
                onPdf: () async {
                  final filas = await _filasDeudores();
                  await _exportarListaPdf(
                    titulo: 'CLIENTES DEUDORES',
                    archivo: 'clientes_deudores.pdf',
                    headers: const [
                      'Nombre',
                      'Teléfono',
                      'Saldo',
                      'Ventas pend.',
                      'Última compra',
                    ],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasDeudores();
                  await _exportarListaCsv(
                    archivo: 'clientes_deudores.csv',
                    headers: const [
                      'Nombre',
                      'Teléfono',
                      'Saldo',
                      'Ventas pend.',
                      'Última compra',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasDeudores();
                  await _exportarListaExcel(
                    hoja: 'Deudores',
                    archivo: 'clientes_deudores.xlsx',
                    headers: const [
                      'Nombre',
                      'Teléfono',
                      'Saldo',
                      'Ventas pend.',
                      'Última compra',
                    ],
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.request_quote_rounded,
                titulo: 'Cuentas por cobrar',
                descripcion: 'Ventas con saldo pendiente',
                onPdf: () async {
                  final filas = await _filasCuentasCobrar();
                  await _exportarListaPdf(
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
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasCuentasCobrar();
                  await _exportarListaCsv(
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
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasCuentasCobrar();
                  await _exportarListaExcel(
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
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.payments_rounded,
                titulo: 'Cobros del día',
                descripcion: 'Pagos registrados hoy',
                onPdf: () async {
                  final filas = await _filasCobrosDia();
                  await _exportarListaPdf(
                    titulo: 'COBROS DEL DÍA',
                    archivo: 'cobros_dia.pdf',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasCobrosDia();
                  await _exportarListaCsv(
                    archivo: 'cobros_dia.csv',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasCobrosDia();
                  await _exportarListaExcel(
                    hoja: 'CobrosDia',
                    archivo: 'cobros_dia.xlsx',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.calendar_month_rounded,
                titulo: 'Cobros del mes',
                descripcion: 'Pagos del mes en curso',
                onPdf: () async {
                  final filas = await _filasCobrosMes();
                  await _exportarListaPdf(
                    titulo: 'COBROS DEL MES',
                    archivo: 'cobros_mes.pdf',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasCobrosMes();
                  await _exportarListaCsv(
                    archivo: 'cobros_mes.csv',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasCobrosMes();
                  await _exportarListaExcel(
                    hoja: 'CobrosMes',
                    archivo: 'cobros_mes.xlsx',
                    headers: const [
                      'Fecha',
                      'Cliente',
                      'Comprobante',
                      'Monto',
                      'Medio',
                    ],
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.summarize_rounded,
                titulo: 'Deuda total',
                descripcion: 'Resumen de deuda acumulada',
                onPdf: () async {
                  final filas = await _filasDeudaTotal();
                  await _exportarListaPdf(
                    titulo: 'DEUDA TOTAL',
                    archivo: 'deuda_total.pdf',
                    headers: const ['Concepto', 'Valor'],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasDeudaTotal();
                  await _exportarListaCsv(
                    archivo: 'deuda_total.csv',
                    headers: const ['Concepto', 'Valor'],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasDeudaTotal();
                  await _exportarListaExcel(
                    hoja: 'Deuda',
                    archivo: 'deuda_total.xlsx',
                    headers: const ['Concepto', 'Valor'],
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.local_shipping_rounded,
                titulo: 'Lista de proveedores',
                descripcion: 'Datos de contacto y condiciones comerciales',
                onPdf: () async {
                  final filas = await _filasProveedores();
                  await _exportarListaPdf(
                    titulo: 'LISTA DE PROVEEDORES',
                    archivo: 'proveedores.pdf',
                    headers: const [
                      'Nombre',
                      'Contacto',
                      'Teléfono',
                      'Email',
                      'Condiciones',
                    ],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasProveedores();
                  await _exportarListaCsv(
                    archivo: 'proveedores.csv',
                    headers: const [
                      'Nombre',
                      'Contacto',
                      'Teléfono',
                      'Email',
                      'Condiciones',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasProveedores();
                  await _exportarListaExcel(
                    hoja: 'Proveedores',
                    archivo: 'proveedores.xlsx',
                    headers: const [
                      'Nombre',
                      'Contacto',
                      'Teléfono',
                      'Email',
                      'Condiciones',
                    ],
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.description_rounded,
                titulo: 'Resumen de remitos',
                descripcion: 'Cliente, fecha, estado y total facturado',
                onPdf: () async {
                  final filas = await _filasRemitos();
                  await _exportarListaPdf(
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
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasRemitos();
                  await _exportarListaCsv(
                    archivo: 'remitos.csv',
                    headers: const [
                      'Número',
                      'Cliente',
                      'Fecha',
                      'Estado',
                      'Pago',
                      'Total',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasRemitos();
                  await _exportarListaExcel(
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
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.shopping_cart_rounded,
                titulo: 'Resumen de compras',
                descripcion: 'Proveedor, factura, estado y total comprado',
                onPdf: () async {
                  final filas = await _filasCompras();
                  await _exportarListaPdf(
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
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasCompras();
                  await _exportarListaCsv(
                    archivo: 'compras.csv',
                    headers: const [
                      'Número',
                      'Factura',
                      'Proveedor',
                      'Fecha',
                      'Estado',
                      'Total',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasCompras();
                  await _exportarListaExcel(
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
                    filas: filas,
                  );
                },
              ),
              _tarjetaReporte(
                icon: Icons.warehouse_rounded,
                titulo: 'Inventario con valor',
                descripcion: 'Stock valorizado a costo por producto',
                onPdf: () async {
                  final filas = await _filasInventario();
                  await _exportarListaPdf(
                    titulo: 'INVENTARIO CON VALOR',
                    archivo: 'inventario_valor.pdf',
                    headers: const [
                      'Código',
                      'Descripción',
                      'Stock',
                      'Costo unit.',
                      'Valor total',
                    ],
                    filas: filas,
                  );
                },
                onCsv: () async {
                  final filas = await _filasInventario();
                  await _exportarListaCsv(
                    archivo: 'inventario_valor.csv',
                    headers: const [
                      'Código',
                      'Descripción',
                      'Stock',
                      'Costo unit.',
                      'Valor total',
                    ],
                    filas: filas,
                  );
                },
                onExcel: () async {
                  final filas = await _filasInventario();
                  await _exportarListaExcel(
                    hoja: 'Inventario',
                    archivo: 'inventario_valor.xlsx',
                    headers: const [
                      'Código',
                      'Descripción',
                      'Stock',
                      'Costo unit.',
                      'Valor total',
                    ],
                    filas: filas,
                  );
                },
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
