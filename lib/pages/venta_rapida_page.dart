import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/config/platform_capabilities.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/sync/cloud_sync_throttle.dart';
import '../core/sync/sync_background.dart';
import '../core/utils/busqueda_texto.dart';
import '../models/cliente.dart';
import '../models/pago.dart';
import '../models/producto.dart';
import '../models/remito.dart';
import '../models/remito_detalle.dart';
import '../services/cliente_service.dart';
import '../services/documento_cliente_service.dart';
import '../services/pdf_service.dart';
import '../services/producto_service.dart';
import '../services/remito_service.dart';
import '../theme/app_tokens.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cobrar_dialog.dart';
import 'scanner_page.dart';

// ---------------------------------------------------------------------------
// Ítem del carrito
// ---------------------------------------------------------------------------
class _ItemCarrito {
  final Producto producto;
  int cantidad;
  double precioUnitario;

  _ItemCarrito({required this.producto})
      : cantidad = 1, precioUnitario = producto.precio;

  double get subtotal => cantidad * precioUnitario;
}

// ---------------------------------------------------------------------------
// Página principal
// ---------------------------------------------------------------------------
class VentaRapidaPage extends StatefulWidget {
  const VentaRapidaPage({super.key});

  @override
  State<VentaRapidaPage> createState() => _VentaRapidaPageState();
}

class _VentaRapidaPageState extends State<VentaRapidaPage> {
  final ProductoService _prodSvc = ProductoService();
  final RemitoService _remitoSvc = RemitoService();
  final ClienteService _clienteSvc = ClienteService();

  final TextEditingController _busquedaCtrl = TextEditingController();

  List<Producto> _resultados = [];
  List<Producto> _catalogoRapido = [];
  final List<_ItemCarrito> _carrito = [];
  Cliente? _cliente;
  String _medioPago = 'efectivo';
  bool _buscando = false;
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    _prepararPos();
  }

  Future<void> _prepararPos() async {
    final mostrador = await _clienteSvc.obtenerOCrearMostrador();
    final todos = await _prodSvc.obtenerTodos();
    final rapidos = [
      ...todos.where((p) => p.favorito),
      ...todos.where((p) => !p.favorito),
    ].take(40).toList();
    if (!mounted) return;
    setState(() {
      _cliente ??= mostrador;
      _catalogoRapido = rapidos;
    });
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    if (_busquedaCtrl.text.trim().isNotEmpty) {
      _buscar(_busquedaCtrl.text);
    } else {
      _prepararPos();
    }
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirCliente() async {
    final clientes = await _clienteSvc.obtenerTodos();
    if (!mounted) return;
    final elegido = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtrados = clientes
                .where(
                  (c) => BusquedaTexto.coincide(filtro, [
                    c.nombre,
                    c.apellido,
                    c.cuit,
                    c.telefono,
                  ]),
                )
                .take(40)
                .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Buscar cliente…',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setLocal(() => filtro = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (_, i) {
                        final c = filtrados[i];
                        final nombre = c.apellido.isEmpty
                            ? c.nombre
                            : '${c.nombre} ${c.apellido}';
                        return ListTile(
                          leading: const Icon(Icons.person_rounded),
                          title: Text(nombre),
                          subtitle: Text(c.telefono.isEmpty ? c.cuit : c.telefono),
                          onTap: () => Navigator.pop(ctx, c),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (elegido != null && mounted) {
      setState(() => _cliente = elegido);
    }
  }

  // ---------------------------------------------------------------------------
  // Búsqueda
  // ---------------------------------------------------------------------------
  Future<void> _buscar(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    // Match exacto por código de barras primero (escáner)
    final porBarras = await _prodSvc.buscarPorCodigoBarras(query.trim());
    if (porBarras != null) {
      if (!mounted) return;
      setState(() {
        _resultados = [porBarras];
        _buscando = false;
      });
      // Si es match exacto de barras, agregar directo
      if (porBarras.codigoBarras == query.trim() ||
          porBarras.codigo == query.trim()) {
        _agregarAlCarrito(porBarras);
        return;
      }
    }
    final todos = await _prodSvc.obtenerTodos();
    final filtrados = todos
        .where(
          (p) => BusquedaTexto.coincide(query, [
            p.descripcion,
            p.codigo,
            p.codigoBarras,
            p.marca,
            p.modelo,
            p.colorProducto,
            p.talle,
          ]),
        )
        .take(40)
        .toList();
    if (!mounted) return;
    setState(() {
      _resultados = filtrados;
      _buscando = false;
    });
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || codigo.trim().isEmpty || !mounted) return;
    _busquedaCtrl.text = codigo.trim();
    await _buscar(codigo.trim());
  }

  // ---------------------------------------------------------------------------
  // Carrito
  // ---------------------------------------------------------------------------
  void _agregarAlCarrito(Producto producto) {
    final idx = _carrito.indexWhere((e) => e.producto.id == producto.id);
    setState(() {
      if (idx >= 0) {
        _carrito[idx].cantidad++;
      } else {
        _carrito.add(_ItemCarrito(producto: producto));
      }
      _resultados = [];
      _busquedaCtrl.clear();
    });
  }

  void _cambiarCantidad(int idx, int delta) {
    setState(() {
      _carrito[idx].cantidad += delta;
      if (_carrito[idx].cantidad <= 0) {
        _carrito.removeAt(idx);
      }
    });
  }

  void _eliminarItem(int idx) {
    setState(() => _carrito.removeAt(idx));
  }

  void _editarPrecio(int idx) async {
    final ctrl = TextEditingController(
      text: _carrito[idx].precioUnitario.toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Precio - ${_carrito[idx].producto.descripcion}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '\$',
            labelText: 'Precio unitario',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) {
      final nuevo = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (nuevo != null && nuevo >= 0) {
        setState(() => _carrito[idx].precioUnitario = nuevo);
      }
    }
  }

  double get _total => _carrito.fold(0, (s, e) => s + e.subtotal);

  // ---------------------------------------------------------------------------
  // Finalizar venta
  // ---------------------------------------------------------------------------
  Future<void> _finalizarVenta() async {
    if (_carrito.isEmpty || _finalizando) return;
    setState(() => _finalizando = true);

    final abonadoCtrl = TextEditingController(text: _total.toStringAsFixed(2));
    var medioPago = _medioPago;

    final confirmar = await showDialog<({bool ok, double abonado, String medio})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final abonado = (double.tryParse(
                      abonadoCtrl.text.replaceAll(',', '.'),
                    ) ??
                    0)
                .clamp(0, _total)
                .toDouble();
            final saldo = (_total - abonado).clamp(0, _total).toDouble();
            final estado = Remito.estadoDesdeMontos(_total, abonado);
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('Finalizar venta'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total: \$${_total.toStringAsFixed(2)}'),
                    Text('${_carrito.length} productos'),
                    const SizedBox(height: 12),
                    const Text(
                      'Cobro ahora (mostrador). Si queda saldo, va a cuenta corriente.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: abonadoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Monto abonado',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixText: '\$ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: medioPago,
                      decoration: const InputDecoration(
                        labelText: 'Medio de pago',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: Pago.mediosPago
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(Pago.labelMedio(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => medioPago = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Saldo: \$${saldo.toStringAsFixed(2)}'
                            '${saldo > 0.009 ? ' → CC' : ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colorEstadoPago(estado, cs),
                            ),
                          ),
                        ),
                        chipEstadoPago(estado, cs),
                      ],
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () {
                            abonadoCtrl.text = '0';
                            setLocal(() {});
                          },
                          child: const Text('Pendiente'),
                        ),
                        TextButton(
                          onPressed: () {
                            abonadoCtrl.text =
                                (_total / 2).toStringAsFixed(2);
                            setLocal(() {});
                          },
                          child: const Text('Parcial'),
                        ),
                        TextButton(
                          onPressed: () {
                            abonadoCtrl.text = _total.toStringAsFixed(2);
                            setLocal(() {});
                          },
                          child: const Text('Cobrado'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    (ok: true, abonado: abonado, medio: medioPago),
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    abonadoCtrl.dispose();
    if (confirmar == null || confirmar.ok != true) {
      if (mounted) setState(() => _finalizando = false);
      return;
    }

    try {
      final cliente =
          _cliente ?? await _clienteSvc.obtenerOCrearMostrador();
      final numero = await _remitoSvc.generarNumero();
      final abonado = confirmar.abonado.clamp(0, _total).toDouble();
      final saldo = (_total - abonado).clamp(0, _total).toDouble();
      final estadoPago = Remito.estadoDesdeMontos(_total, abonado);

      final remito = Remito(
        numero: numero,
        fecha: DateTime.now(),
        tipo: 'salida',
        clienteId: cliente.id?.toString(),
        estado: 'confirmado',
        estadoPago: estadoPago,
        totalPagado: abonado,
        saldoPendiente: saldo,
        observaciones: 'Venta rápida en mostrador',
        total: _total,
      );

      final items = _carrito
          .map(
            (e) => RemitoDetalle(
              remitoId: 0,
              productoId: e.producto.id!,
              cantidad: e.cantidad,
              precioUnitario: e.precioUnitario,
              subtotal: e.subtotal,
              costoUnitario: e.producto.costo,
            ),
          )
          .toList();

      final remitoId = await _remitoSvc.insertar(
        remito,
        items,
        medioPago: confirmar.medio,
      );
      final totalVenta = remito.total;
      final carritoSnapshot = List<_ItemCarrito>.from(_carrito);

      if (!mounted) return;
      setState(() {
        _carrito.clear();
        _finalizando = false;
      });

      final remitoMap = {
        'id': remitoId,
        'numero': numero,
        'fecha': remito.fecha.toIso8601String(),
        'total': remito.total,
        'descuento': 0,
      };
      final itemsPdf = carritoSnapshot
          .map(
            (e) => {
              'descripcion': e.producto.descripcion,
              'cantidad': e.cantidad,
              'precio': e.precioUnitario,
              'subtotal': e.subtotal,
            },
          )
          .toList();
      final clienteNombre = cliente.nombre;
      final clienteId = cliente.id;
      final clienteSyncId = cliente.syncId;

      Future<File?> generarPdfLocal() async {
        final pdfSvc = PdfService();
        final bytes = await pdfSvc.generateRemitoPdf(
          remitoMap,
          itemsPdf,
          clienteNombre,
        );
        if (bytes.isEmpty) return null;
        return pdfSvc.guardarPdf(bytes, 'remito_$numero.pdf');
      }

      Future<void> archivar(File archivo) async {
        await DocumentoClienteService.instance.archivarPdf(
          archivo: archivo,
          tipo: 'remito',
          numero: numero,
          clienteNombre: clienteNombre,
          clienteId: clienteId,
          clienteSyncId: clienteSyncId,
        );
      }

      // Windows: NO generar PDF ni Storage al instante (crash .exe con sync).
      // Android/otros: archivo local en background como antes.
      if (PlatformCapabilities.isWindowsDesktop) {
        syncInBackground(
          CloudSyncThrottle.enqueue(() async {
            await Future<void>.delayed(const Duration(seconds: 15));
            try {
              final archivo = await generarPdfLocal();
              if (archivo != null) await archivar(archivo);
            } catch (_) {}
          }, tag: 'ventaRapidaPdf'),
          tag: 'ventaRapidaPdf',
        );
      } else {
        unawaited(() async {
          try {
            final archivo = await generarPdfLocal();
            if (archivo != null) await archivar(archivo);
          } catch (_) {}
        }());
      }

      final compartir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Venta registrada'),
          content: Text(
            'Comprobante $numero · Total \$${totalVenta.toStringAsFixed(2)}\n'
            'Pago: ${remito.estadoPago}'
            '${remito.saldoPendiente > 0.009 ? ' · CC \$${remito.saldoPendiente.toStringAsFixed(2)}' : ''}\n'
            'Guardado en este equipo'
            '${_tieneRedHint()}.\n\n¿Compartir el PDF ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Después'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartir PDF'),
            ),
          ],
        ),
      );

      if (compartir == true && mounted) {
        try {
          final archivo = await generarPdfLocal();
          if (archivo != null) {
            // Archivo local ya; nube va diferida (Windows) o por archivarPdf.
            unawaited(archivar(archivo));
            await SharePlus.instance.share(
              ShareParams(files: [XFile(archivo.path)], text: numero),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo compartir PDF: $e')),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Venta registrada · Comprobante $numero · Total \$${totalVenta.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _finalizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar la venta: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _tieneRedHint() =>
      '. Si no hay internet, se sincroniza después';

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  String get _clienteLabel {
    final c = _cliente;
    if (c == null) return 'Mostrador';
    return c.apellido.isEmpty ? c.nombre : '${c.nombre} ${c.apellido}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Venta rápida',
        actions: [
          if (_carrito.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.shopping_cart_rounded, size: 16),
                  label: Text('${_carrito.length} ítems'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 55, child: _panelProductos(context)),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(flex: 45, child: _panelCobro(context)),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: _carrito.isEmpty ? 1 : 3, child: _panelProductos(context)),
              if (_carrito.isNotEmpty) ...[
                const Divider(height: 1),
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    itemCount: _carrito.length,
                    itemBuilder: (_, i) => _itemCarritoTile(context, i),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: _barraTotalCompacta(context),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _panelProductos(BuildContext context) {
    final theme = Theme.of(context);
    final lista =
        _resultados.isNotEmpty ? _resultados : _catalogoRapido;
    final buscandoAlgo = _busquedaCtrl.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _busquedaCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar o escanear producto…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Escanear',
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: _escanear,
                  ),
                  if (_busquedaCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _busquedaCtrl.clear();
                        setState(() => _resultados = []);
                      },
                    ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            onChanged: _buscar,
            onSubmitted: _buscar,
          ),
        ),
        if (_buscando) const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              buscandoAlgo ? 'Resultados' : 'Productos rápidos',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text(
                    buscandoAlgo
                        ? 'Sin productos para esa búsqueda'
                        : 'Escribí o escaneá para empezar',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = lista[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          p.descripcion.isNotEmpty
                              ? p.descripcion[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        p.descripcion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.codigo} · Stock ${p.stock}'
                        '${p.marca.isNotEmpty ? ' · ${p.marca}' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        '\$${p.precio.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      onTap: () => _agregarAlCarrito(p),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _panelCobro(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            child: InkWell(
              onTap: _elegirCliente,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cliente',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _clienteLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Carrito',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Expanded(
          child: _carrito.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 56,
                        color: cs.onSurface.withValues(alpha: .28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agregá productos desde la izquierda',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  itemCount: _carrito.length,
                  itemBuilder: (_, i) => _itemCarritoTile(context, i),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _medioPago,
                decoration: const InputDecoration(
                  labelText: 'Método de pago',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: Pago.mediosPago
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(Pago.labelMedio(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _medioPago = v);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: theme.textTheme.labelMedium),
                        Text(
                          '\$${_total.toStringAsFixed(2)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _finalizando
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: _carrito.isEmpty ? null : _finalizarVenta,
                          icon: const Icon(Icons.point_of_sale_rounded),
                          label: const Text('Finalizar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(150, 48),
                          ),
                        ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barraTotalCompacta(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.person_rounded),
            title: Text(_clienteLabel, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_rounded, size: 18),
            onTap: _elegirCliente,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '\$${_total.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              _finalizando
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _finalizarVenta,
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: const Text('Finalizar'),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemCarritoTile(BuildContext context, int i) {
    final theme = Theme.of(context);
    final item = _carrito[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.producto.descripcion,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  GestureDetector(
                    onTap: () => _editarPrecio(i),
                    child: Text(
                      '\$${item.precioUnitario.toStringAsFixed(2)} · editar',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 18),
              onPressed: () => _cambiarCantidad(i, -1),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            Text(
              '${item.cantidad}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: () => _cambiarCantidad(i, 1),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '\$${item.subtotal.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () => _eliminarItem(i),
              color: theme.colorScheme.error.withValues(alpha: .7),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
