import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/movimiento_stock.dart';
import '../models/producto.dart';
import '../services/producto_service.dart';
import '../services/stock_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import 'scanner_page.dart';

/// Conteo de inventario por código de barras / cámara.
class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final _productoService = ProductoService();
  final _stockService = StockService();
  final _buscarCtrl = TextEditingController();
  final _contadoCtrl = TextEditingController();

  Producto? _producto;
  bool _buscando = false;
  bool _guardando = false;
  final List<_ConteoSesion> _sesion = [];

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onRefresh);
  }

  void _onRefresh() {
    if (!mounted || _producto?.id == null) return;
    _refrescarProductoActual();
  }

  Future<void> _refrescarProductoActual() async {
    final id = _producto?.id;
    if (id == null) return;
    final todos = await _productoService.obtenerTodos();
    Producto? actualizado;
    for (final prod in todos) {
      if (prod.id == id) {
        actualizado = prod;
        break;
      }
    }
    if (!mounted || actualizado == null) return;
    setState(() => _producto = actualizado);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onRefresh);
    _buscarCtrl.dispose();
    _contadoCtrl.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || codigo.trim().isEmpty || !mounted) return;
    _buscarCtrl.text = codigo.trim();
    await _buscar(codigo.trim());
  }

  Future<void> _buscar([String? texto]) async {
    final q = (texto ?? _buscarCtrl.text).trim();
    if (q.isEmpty) return;
    setState(() {
      _buscando = true;
      _producto = null;
    });
    try {
      Producto? encontrado =
          await _productoService.buscarPorCodigoBarras(q);
      if (encontrado == null) {
        final todos = await _productoService.obtenerTodos();
        final lower = q.toLowerCase();
        final matches = todos
            .where(
              (p) =>
                  p.codigo.toLowerCase() == lower ||
                  p.codigoBarras.toLowerCase() == lower ||
                  p.descripcion.toLowerCase().contains(lower),
            )
            .toList();
        if (matches.length == 1) {
          encontrado = matches.first;
        } else if (matches.length > 1 && mounted) {
          encontrado = await showModalBottomSheet<Producto>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Varios productos coinciden',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ...matches.map(
                    (p) => ListTile(
                      title: Text(p.descripcion),
                      subtitle: Text(
                        '${p.codigo}${p.codigoBarras.isNotEmpty ? ' · ${p.codigoBarras}' : ''} · Stock ${p.stock}',
                      ),
                      onTap: () => Navigator.pop(ctx, p),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _producto = encontrado;
        if (encontrado != null) {
          _contadoCtrl.text = '${encontrado.stock}';
        }
      });
      if (encontrado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se encontró producto para "$q"')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _confirmarConteo() async {
    final producto = _producto;
    if (producto?.id == null) return;
    final contado = int.tryParse(_contadoCtrl.text.trim());
    if (contado == null || contado < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá una cantidad válida (≥ 0).')),
      );
      return;
    }
    final delta = contado - producto!.stock;
    if (delta == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El stock ya coincide con el conteo.')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await _stockService.registrarMovimiento(
        MovimientoStock(
          productoId: producto.id!,
          tipo: delta >= 0 ? 'entrada' : 'salida',
          cantidad: delta.abs(),
          fecha: DateTime.now(),
          motivo: 'Conteo de inventario (sistema: ${producto.stock} → $contado)',
        ),
      );
      if (!mounted) return;
      setState(() {
        _sesion.insert(
          0,
          _ConteoSesion(
            descripcion: producto.descripcion,
            codigo: producto.codigo,
            anterior: producto.stock,
            contado: contado,
          ),
        );
        _producto = producto.copyWith(stock: contado);
        _contadoCtrl.text = '$contado';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock actualizado: ${producto.descripcion} → $contado',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _producto;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Inventario',
        actions: [
          IconButton(
            tooltip: 'Escanear',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _buscando || _guardando ? null : _escanear,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_inventario_scan',
        onPressed: _buscando || _guardando ? null : _escanear,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Escanear'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'Escaneá o buscá un producto y cargá el stock contado.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscarCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _buscar,
            decoration: InputDecoration(
              hintText: 'Código, barras o descripción',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _buscando ? null : () => _buscar(),
                icon: _buscando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (p != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.descripcion,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (p.codigo.isNotEmpty) 'Cód. ${p.codigo}',
                        if (p.codigoBarras.isNotEmpty) 'Barras ${p.codigoBarras}',
                      ].join(' · '),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _dato(
                            'Stock sistema',
                            '${p.stock}',
                            AppVisuals.info(cs),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dato(
                            'Mínimo',
                            '${p.stockMinimo}',
                            AppVisuals.warning(cs),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _contadoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Stock contado *',
                        border: OutlineInputBorder(),
                        helperText: 'Cantidad física en el depósito',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _guardando ? null : _confirmarConteo,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _guardando ? 'Guardando...' : 'Confirmar conteo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_buscando) ...[
            Card(
              child: ListTile(
                leading: Icon(Icons.inventory_2_outlined, color: cs.primary),
                title: const Text('Sin producto seleccionado'),
                subtitle: const Text(
                  'Usá la cámara o escribí un código para empezar el conteo.',
                ),
              ),
            ),
          ],
          if (_sesion.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Conteos de esta sesión',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ..._sesion.map(
              (c) => Card(
                child: ListTile(
                  dense: true,
                  title: Text(c.descripcion, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${c.codigo} · ${c.anterior} → ${c.contado}'),
                  trailing: Icon(
                    c.contado >= c.anterior
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: c.contado >= c.anterior
                        ? AppVisuals.success(cs)
                        : AppVisuals.danger(cs),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dato(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConteoSesion {
  final String descripcion;
  final String codigo;
  final int anterior;
  final int contado;

  _ConteoSesion({
    required this.descripcion,
    required this.codigo,
    required this.anterior,
    required this.contado,
  });
}
